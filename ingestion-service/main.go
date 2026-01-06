package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
)

var (
	redisClient  *redis.Client
	kafkaWriter  *kafka.Writer
	eventChannel chan map[string]interface{}
	workerPool   = 10 // Number of worker goroutines
	ctx          = context.Background()
)

func init() {
	// Initialize Redis client
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "redis:6379"
	}
	redisClient = redis.NewClient(&redis.Options{
		Addr:         redisAddr,
		PoolSize:     20,
		MinIdleConns: 5,
	})

	// Initialize optimized Kafka writer (reusable connection)
	kafkaBrokers := os.Getenv("KAFKA_BROKERS")
	if kafkaBrokers == "" {
		kafkaBrokers = "kafka:9092"
	}
	kafkaWriter = &kafka.Writer{
		Addr:         kafka.TCP(kafkaBrokers),
		Topic:        "raw-events",
		Balancer:     &kafka.LeastBytes{},
		BatchSize:    100,                   // Batch up to 100 messages
		BatchTimeout: 10 * time.Millisecond, // Wait max 10ms for batching
		Compression:  kafka.Gzip,            // Use gzip compression
		Async:        false,                 // Synchronous for reliability
		RequiredAcks: kafka.RequireOne,      // Wait for leader acknowledgment
	}

	// Initialize event channel for async processing
	eventChannel = make(chan map[string]interface{}, 1000)
}

func main() {
	log.Println("Starting optimized ingestion service on :8081")

	// Test Redis connection
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Printf("Warning: Redis connection failed: %v", err)
	} else {
		log.Println("Connected to Redis successfully")
	}

	// Start worker pool for async event processing
	var wg sync.WaitGroup
	for i := 0; i < workerPool; i++ {
		wg.Add(1)
		go eventWorker(i, &wg)
	}

	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/events", eventsHandler)
	http.HandleFunc("/metrics", metricsHandler)

	log.Println("Worker pool started with", workerPool, "workers")
	log.Fatal(http.ListenAndServe(":8081", nil))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Check Redis health
	redisStatus := "healthy"
	if err := redisClient.Ping(ctx).Err(); err != nil {
		redisStatus = "unhealthy: " + err.Error()
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "healthy",
		"time":        time.Now().UTC().Format(time.RFC3339),
		"redis":       redisStatus,
		"queue_depth": len(eventChannel),
	})
}

func eventsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var event map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&event); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Check for duplicate events using Redis
	eventID := generateEventID(event)
	isDuplicate, err := checkDuplicate(eventID)
	if err != nil {
		log.Printf("Redis check failed: %v", err)
	} else if isDuplicate {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "duplicate",
			"message": "Event already processed",
		})
		return
	}

	// Enrich event with metadata
	event["ingested_at"] = time.Now().UTC().Format(time.RFC3339)
	event["service"] = "ingestion"
	event["event_id"] = eventID

	// Send to async worker pool (non-blocking)
	select {
	case eventChannel <- event:
		// Event queued successfully
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":   "accepted",
			"message":  "Event queued for processing",
			"event_id": eventID,
		})
	default:
		// Channel full, reject with backpressure
		http.Error(w, "Service overloaded, try again later", http.StatusServiceUnavailable)
	}
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Get cache stats from Redis
	var cacheHits, cacheMisses int64
	if val, err := redisClient.Get(ctx, "metrics:cache_hits").Int64(); err == nil {
		cacheHits = val
	}
	if val, err := redisClient.Get(ctx, "metrics:cache_misses").Int64(); err == nil {
		cacheMisses = val
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"queue_depth":  len(eventChannel),
		"cache_hits":   cacheHits,
		"cache_misses": cacheMisses,
		"timestamp":    time.Now().UTC().Format(time.RFC3339),
	})
}

// Worker goroutine for async event processing
func eventWorker(id int, wg *sync.WaitGroup) {
	defer wg.Done()
	log.Printf("Worker %d started", id)

	for event := range eventChannel {
		if err := processEvent(event); err != nil {
			log.Printf("Worker %d: Failed to process event: %v", id, err)
		}
	}
}

func processEvent(event map[string]interface{}) error {
	eventID, _ := event["event_id"].(string)

	// Send to Kafka
	jsonData, err := json.Marshal(event)
	if err != nil {
		return err
	}

	err = kafkaWriter.WriteMessages(ctx, kafka.Message{
		Key:   []byte(eventID),
		Value: jsonData,
	})

	if err != nil {
		return err
	}

	// Mark as processed in Redis (TTL 1 hour for deduplication)
	redisClient.Set(ctx, "event:"+eventID, "1", time.Hour)

	log.Printf("Event processed: %s", eventID)
	return nil
}

// Generate unique event ID from event content
func generateEventID(event map[string]interface{}) string {
	data, _ := json.Marshal(event)
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}

// Check if event was already processed (deduplication)
func checkDuplicate(eventID string) (bool, error) {
	exists, err := redisClient.Exists(ctx, "event:"+eventID).Result()
	if err != nil {
		redisClient.Incr(ctx, "metrics:cache_misses")
		return false, err
	}

	if exists > 0 {
		redisClient.Incr(ctx, "metrics:cache_hits")
		return true, nil
	}

	redisClient.Incr(ctx, "metrics:cache_misses")
	return false, nil
}
