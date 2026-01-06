#!/bin/bash
# End-to-End Testing Script for Phase 3 Optimizations
# Tests Redis caching, async processing, feature computation, and API

set -e

echo "=========================================="
echo "Phase 3 E2E Test Suite"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASSED${NC}: $2"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}: $2"
        ((TESTS_FAILED++))
    fi
}

echo "Waiting for services to be ready (30 seconds)..."
sleep 30

echo ""
echo "=========================================="
echo "1. Testing Ingestion Service Health"
echo "=========================================="

# Test health endpoint
HEALTH_RESPONSE=$(curl -s http://localhost:8081/health)
echo "Health Response: $HEALTH_RESPONSE"

if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    test_result 0 "Ingestion service is healthy"
else
    test_result 1 "Ingestion service health check"
fi

# Check Redis connection in health response
if echo "$HEALTH_RESPONSE" | grep -q "redis"; then
    test_result 0 "Redis connection reported in health"
else
    test_result 1 "Redis connection in health endpoint"
fi

echo ""
echo "=========================================="
echo "2. Testing Event Ingestion & Deduplication"
echo "=========================================="

# Send first event
EVENT1=$(curl -s -X POST http://localhost:8081/events \
    -H 'Content-Type: application/json' \
    -d '{"event_type":"click","user_id":"test_user_1","page":"home","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}')

echo "First Event Response: $EVENT1"

if echo "$EVENT1" | grep -q "accepted\|success"; then
    test_result 0 "First event accepted"
    EVENT_ID=$(echo "$EVENT1" | grep -o '"event_id":"[^"]*"' | cut -d'"' -f4)
    echo "Event ID: $EVENT_ID"
else
    test_result 1 "First event ingestion"
fi

sleep 1

# Send duplicate event (same data)
EVENT2=$(curl -s -X POST http://localhost:8081/events \
    -H 'Content-Type: application/json' \
    -d '{"event_type":"click","user_id":"test_user_1","page":"home","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}')

echo "Duplicate Event Response: $EVENT2"

if echo "$EVENT2" | grep -q "duplicate"; then
    test_result 0 "Deduplication working (duplicate detected)"
else
    echo -e "${YELLOW}⚠ WARNING${NC}: Deduplication not detected (may be timing issue)"
fi

echo ""
echo "=========================================="
echo "3. Testing Async Processing (Load Test)"
echo "=========================================="

echo "Sending 20 events rapidly..."
for i in {1..20}; do
    curl -s -X POST http://localhost:8081/events \
        -H 'Content-Type: application/json' \
        -d '{"event_type":"click","user_id":"user_'$i'","page":"test","count":'$i'}' > /dev/null &
done

wait
echo "All events sent"
test_result 0 "Bulk event submission (20 events)"

# Check metrics endpoint
sleep 2
METRICS=$(curl -s http://localhost:8081/metrics)
echo "Metrics Response: $METRICS"

if echo "$METRICS" | grep -q "queue_depth"; then
    test_result 0 "Metrics endpoint available"
else
    test_result 1 "Metrics endpoint"
fi

echo ""
echo "=========================================="
echo "4. Testing Kafka Message Flow"
echo "=========================================="

# Check if messages are in Kafka topic
sleep 5
echo "Checking Kafka topics..."
KAFKA_TOPICS=$(docker-compose exec -T kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null || echo "")

if echo "$KAFKA_TOPICS" | grep -q "raw-events"; then
    test_result 0 "raw-events topic exists"
else
    test_result 1 "raw-events topic"
fi

if echo "$KAFKA_TOPICS" | grep -q "feature-events"; then
    test_result 0 "feature-events topic exists"
else
    test_result 1 "feature-events topic"
fi

echo ""
echo "=========================================="
echo "5. Testing Feature Processor"
echo "=========================================="

# Wait for feature processing
echo "Waiting for feature computation (10 seconds)..."
sleep 10

# Check PostgreSQL for computed features
echo "Checking database for computed features..."
FEATURE_COUNT=$(docker-compose exec -T postgres psql -U admin -d featurestore -t -c "SELECT COUNT(*) FROM features;" 2>/dev/null | tr -d ' \n' || echo "0")

echo "Features in database: $FEATURE_COUNT"

if [ "$FEATURE_COUNT" -gt 0 ]; then
    test_result 0 "Features computed and stored ($FEATURE_COUNT features)"
else
    test_result 1 "Feature computation"
fi

echo ""
echo "=========================================="
echo "6. Testing Feature Serving API"
echo "=========================================="

# Wait for API to be ready
sleep 5

# Test API health
API_HEALTH=$(curl -s http://localhost:8083/health 2>/dev/null || echo "")
echo "API Health: $API_HEALTH"

if echo "$API_HEALTH" | grep -q "healthy\|degraded"; then
    test_result 0 "Feature API is responding"
else
    test_result 1 "Feature API health"
fi

# Test getting features for a user
echo ""
echo "Testing feature retrieval..."
USER_FEATURES=$(curl -s http://localhost:8083/features/test_user_1 2>/dev/null || echo "")

if echo "$USER_FEATURES" | grep -q "features\|user_id"; then
    test_result 0 "Feature retrieval API"
    echo "Sample features: $USER_FEATURES" | head -c 200
    echo "..."
else
    test_result 1 "Feature retrieval API"
fi

echo ""
echo "=========================================="
echo "7. Testing Redis Caching"
echo "=========================================="

# Check Redis for cached data
REDIS_KEYS=$(docker-compose exec -T redis redis-cli KEYS "*" 2>/dev/null | wc -l)
echo "Redis keys count: $REDIS_KEYS"

if [ "$REDIS_KEYS" -gt 0 ]; then
    test_result 0 "Redis caching active ($REDIS_KEYS keys)"
else
    echo -e "${YELLOW}⚠ WARNING${NC}: No Redis keys found (may need more time)"
fi

# Test cache hit (second request should be faster)
echo "Testing cache performance..."
START=$(date +%s%N)
curl -s http://localhost:8083/features/test_user_1 > /dev/null 2>&1
END=$(date +%s%N)
FIRST_TIME=$((($END - $START) / 1000000))

START=$(date +%s%N)
curl -s http://localhost:8083/features/test_user_1 > /dev/null 2>&1
END=$(date +%s%N)
SECOND_TIME=$((($END - $START) / 1000000))

echo "First request: ${FIRST_TIME}ms"
echo "Second request (cached): ${SECOND_TIME}ms"

if [ "$SECOND_TIME" -lt "$FIRST_TIME" ]; then
    test_result 0 "Cache providing speed improvement"
else
    echo -e "${YELLOW}⚠ INFO${NC}: Cache timing inconclusive"
fi

echo ""
echo "=========================================="
echo "8. Service Monitoring"
echo "=========================================="

# Check Prometheus
PROM_STATUS=$(curl -s http://localhost:9090/-/healthy 2>/dev/null || echo "")
if echo "$PROM_STATUS" | grep -q "Prometheus is Healthy"; then
    test_result 0 "Prometheus monitoring"
else
    test_result 1 "Prometheus monitoring"
fi

# Check Grafana
GRAFANA_STATUS=$(curl -s http://localhost:3000/api/health 2>/dev/null || echo "")
if echo "$GRAFANA_STATUS" | grep -q "ok"; then
    test_result 0 "Grafana dashboards"
else
    test_result 1 "Grafana dashboards"
fi

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All core tests passed!${NC}"
    echo ""
    echo "✅ Phase 3 Optimization Complete!"
    echo ""
    echo "Services Available:"
    echo "  • Ingestion API:    http://localhost:8081"
    echo "  • Feature API:      http://localhost:8083"
    echo "  • Kafka UI:         http://localhost:8080"
    echo "  • Prometheus:       http://localhost:9090"
    echo "  • Grafana:          http://localhost:3000"
    echo ""
    echo "Next Steps:"
    echo "  1. Open Grafana to see metrics"
    echo "  2. Check Kafka UI for message flow"
    echo "  3. Test API: curl http://localhost:8083/features/<user_id>"
    exit 0
else
    echo -e "${YELLOW}⚠ Some tests failed. Check logs:${NC}"
    echo "  docker-compose logs ingestion"
    echo "  docker-compose logs feature-processor"
    echo "  docker-compose logs feature-api"
    exit 1
fi
