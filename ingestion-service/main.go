package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/segmentio/kafka-go"
)

func main() {
	log.Println("Starting ingestion service on :8081")

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status": "healthy",
			"time":   time.Now().UTC().Format(time.RFC3339),
		})
	})

	http.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var event map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&event); err != nil {
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}

		event["ingested_at"] = time.Now().UTC().Format(time.RFC3339)
		event["service"] = "ingestion"

		if err := sendToKafka(event); err != nil {
			log.Printf("Failed to send to Kafka: %v", err)
			http.Error(w, "Failed to process event", http.StatusInternalServerError)
			return
		}

		log.Printf("Event sent to Kafka: %v", event)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "success",
			"message": "Event sent to Kafka",
			"event":   event,
		})
	})

	log.Fatal(http.ListenAndServe(":8081", nil))
}

func sendToKafka(event map[string]interface{}) error {
	jsonData, err := json.Marshal(event)
	if err != nil {
		return err
	}

	writer := &kafka.Writer{
		Addr:  kafka.TCP("kafka:9092"),
		Topic: "raw-events",
	}
	defer writer.Close()

	return writer.WriteMessages(context.Background(),
		kafka.Message{Value: jsonData},
	)
}
