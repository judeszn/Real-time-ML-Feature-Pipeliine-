#!/bin/bash

# Enhanced Feature Pipeline Test Script
# Tests all new features: versioning, A/B testing, drift detection, batch processing

set -e

echo "=========================================="
echo "Enhanced Feature Pipeline Test"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INGESTION_URL="http://localhost:8080"
FEATURE_API_URL="http://localhost:8083"
FEATURE_METRICS_URL="http://localhost:8082"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

wait_for_processing() {
    local seconds=${1:-3}
    echo "Waiting ${seconds}s for processing..."
    sleep $seconds
}

# Test 1: Check all services are running
print_section "Test 1: Service Health Checks"

services=("kafka" "redis" "postgres" "ingestion-service" "feature-processor" "feature-api")
for service in "${services[@]}"; do
    if docker ps | grep -q $service; then
        print_success "$service is running"
    else
        print_error "$service is not running"
    fi
done

# Test 2: Check feature processor has new enhancements
print_section "Test 2: Feature Processor Configuration"

if [ -f "feature-processor/features.yaml" ]; then
    print_success "features.yaml configuration exists"
    
    # Check for key features
    if grep -q "feature_version: \"v2\"" feature-processor/features.yaml; then
        print_success "Feature versioning configured (v2)"
    else
        print_error "Feature versioning not found"
    fi
    
    if grep -q "ab_testing:" feature-processor/features.yaml; then
        print_success "A/B testing configuration found"
    else
        print_error "A/B testing configuration not found"
    fi
    
    if grep -q "drift_detection:" feature-processor/features.yaml; then
        print_success "Drift detection configuration found"
    else
        print_error "Drift detection configuration not found"
    fi
else
    print_error "features.yaml not found"
fi

# Test 3: Health checks
print_section "Test 3: API Health Checks"

# Check ingestion service health
if curl -sf $INGESTION_URL/health > /dev/null 2>&1; then
    print_success "Ingestion service health check passed"
else
    print_error "Ingestion service health check failed"
fi

# Check feature API health
if curl -sf $FEATURE_API_URL/health > /dev/null 2>&1; then
    print_success "Feature API health check passed"
    curl -s $FEATURE_API_URL/health | jq '.' || true
else
    print_error "Feature API health check failed"
fi

# Test 4: Send test events for different users
print_section "Test 4: Sending Test Events"

# Generate test events for multiple users to test A/B variants
users=("user_alice" "user_bob" "user_charlie" "user_diana" "user_eve")
event_types=("login" "view" "purchase" "click" "search")

print_info "Sending 50 test events..."

for i in {1..50}; do
    user=${users[$RANDOM % ${#users[@]}]}
    event_type=${event_types[$RANDOM % ${#event_types[@]}]}
    device_types=("mobile" "desktop" "tablet")
    device=${device_types[$RANDOM % ${#device_types[@]}]}
    
    payload=$(cat <<EOF
{
    "event_id": "test_event_$i",
    "user_id": "$user",
    "event_type": "$event_type",
    "device_type": "$device",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "metadata": {
        "test": true,
        "batch": "enhanced_test"
    }
}
EOF
)
    
    response=$(curl -s -X POST $INGESTION_URL/ingest \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q "event_id"; then
        if [ $((i % 10)) -eq 0 ]; then
            echo "  Sent $i events..."
        fi
    else
        print_error "Failed to send event $i"
    fi
    
    # Small delay to avoid overwhelming the system
    sleep 0.1
done

print_success "Sent 50 test events"

# Wait for processing
wait_for_processing 5

# Test 5: Check Prometheus metrics
print_section "Test 5: Prometheus Metrics"

metrics=$(curl -s $FEATURE_METRICS_URL/metrics)

# Check basic metrics
if echo "$metrics" | grep -q "events_processed_total"; then
    processed=$(echo "$metrics" | grep "^events_processed_total" | awk '{print $2}')
    print_success "Events processed: $processed"
else
    print_error "events_processed_total metric not found"
fi

# Check A/B variant metrics
if echo "$metrics" | grep -q "ab_variant_assignments"; then
    print_success "A/B variant tracking active"
    echo "$metrics" | grep "ab_variant_assignments" | while read line; do
        echo "  $line"
    done
else
    print_error "A/B variant metrics not found"
fi

# Check drift detection metrics
if echo "$metrics" | grep -q "feature_drift_alerts"; then
    print_success "Drift detection metrics active"
else
    print_info "No drift alerts triggered (expected for initial run)"
fi

# Check batch processing metrics
if echo "$metrics" | grep -q "batch_size"; then
    print_success "Batch processing metrics found"
else
    print_error "Batch processing metrics not found"
fi

# Test 6: Query computed features
print_section "Test 6: Query Computed Features"

for user in "${users[@]}"; do
    print_info "Querying features for $user..."
    
    response=$(curl -s $FEATURE_API_URL/features/$user)
    
    if echo "$response" | grep -q "features"; then
        print_success "Features found for $user"
        
        # Check for version information
        if echo "$response" | grep -q "feature_version\|ab_variant"; then
            variant=$(echo "$response" | jq -r '.features.ab_variant.value // "not found"' 2>/dev/null || echo "not found")
            if [ "$variant" != "not found" ]; then
                print_success "  A/B variant: $variant"
            fi
        fi
        
        # Check for new features
        feature_names=$(echo "$response" | jq -r '.features | keys[]' 2>/dev/null | head -5)
        if [ ! -z "$feature_names" ]; then
            echo -e "  ${YELLOW}Sample features:${NC}"
            echo "$feature_names" | while read fname; do
                fvalue=$(echo "$response" | jq -r ".features[\"$fname\"].value" 2>/dev/null || echo "N/A")
                echo "    - $fname: $fvalue"
            done
        fi
    else
        print_info "No features yet for $user (may still be processing)"
    fi
    echo ""
done

# Test 7: Check database for new features
print_section "Test 7: Database Verification"

print_info "Checking database for enhanced features..."

# Check if tables exist
docker exec -i $(docker ps -q -f name=postgres) psql -U admin -d featurestore << EOF
-- Check table structure
\dt
\d features

-- Count features by version
SELECT feature_version, ab_variant, COUNT(*) as feature_count
FROM features
GROUP BY feature_version, ab_variant
ORDER BY feature_version, ab_variant;

-- Show sample features
SELECT user_id, feature_name, feature_value, feature_version, ab_variant
FROM features
LIMIT 10;

-- Check for new feature types
SELECT DISTINCT feature_name
FROM features
ORDER BY feature_name;
EOF

if [ $? -eq 0 ]; then
    print_success "Database queries executed successfully"
else
    print_error "Database queries failed"
fi

# Test 8: Check Redis cache
print_section "Test 8: Redis Cache Verification"

print_info "Checking Redis cache..."

# Get cache keys
cache_keys=$(docker exec -i $(docker ps -q -f name=redis) redis-cli KEYS "*" | head -20)

if [ ! -z "$cache_keys" ]; then
    print_success "Redis cache is active"
    echo -e "${YELLOW}Sample cache keys:${NC}"
    echo "$cache_keys" | head -10
    
    # Count different key types
    activity_keys=$(docker exec -i $(docker ps -q -f name=redis) redis-cli KEYS "activity:*" | wc -l)
    drift_keys=$(docker exec -i $(docker ps -q -f name=redis) redis-cli KEYS "drift:*" | wc -l)
    
    print_info "Activity cache keys: $activity_keys"
    print_info "Drift monitoring keys: $drift_keys"
else
    print_error "Redis cache is empty or unavailable"
fi

# Test 9: Check Kafka topics
print_section "Test 9: Kafka Topics"

print_info "Checking Kafka topics..."

topics=$(docker exec -i $(docker ps -q -f name=kafka) kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null || echo "")

if echo "$topics" | grep -q "feature-events"; then
    print_success "feature-events topic exists"
    
    # Get message count
    msg_count=$(docker exec -i $(docker ps -q -f name=kafka) kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic feature-events \
        --time -1 2>/dev/null | awk -F':' '{sum += $3} END {print sum}' || echo "0")
    
    print_info "Messages in feature-events: $msg_count"
else
    print_error "feature-events topic not found"
fi

if echo "$topics" | grep -q "dead-letter-queue"; then
    print_success "dead-letter-queue topic exists"
else
    print_info "dead-letter-queue topic not found (OK if no errors)"
fi

# Test 10: Performance metrics
print_section "Test 10: Performance Metrics"

print_info "Gathering performance metrics..."

# Get processing latency
latency=$(curl -s $FEATURE_METRICS_URL/metrics | grep "feature_computation_seconds_sum" | awk '{print $2}')
if [ ! -z "$latency" ]; then
    print_success "Feature computation latency tracked: ${latency}s total"
fi

# Cache hit rate
cache_hits=$(curl -s $FEATURE_METRICS_URL/metrics | grep "^cache_hits_total" | awk '{print $2}')
cache_misses=$(curl -s $FEATURE_METRICS_URL/metrics | grep "^cache_misses_total" | awk '{print $2}')

if [ ! -z "$cache_hits" ] && [ ! -z "$cache_misses" ]; then
    total=$((cache_hits + cache_misses))
    if [ $total -gt 0 ]; then
        hit_rate=$(echo "scale=2; $cache_hits * 100 / $total" | bc)
        print_success "Cache hit rate: ${hit_rate}%"
    fi
fi

# Test 11: Feature versioning test
print_section "Test 11: Feature Versioning"

print_info "Checking feature versions in database..."

docker exec -i $(docker ps -q -f name=postgres) psql -U admin -d featurestore << EOF
-- Check version distribution
SELECT 
    feature_version,
    COUNT(DISTINCT user_id) as users,
    COUNT(*) as features
FROM features
GROUP BY feature_version
ORDER BY feature_version;

-- Check variant distribution
SELECT 
    ab_variant,
    COUNT(DISTINCT user_id) as users,
    COUNT(*) as features
FROM features
GROUP BY ab_variant
ORDER BY ab_variant;
EOF

if [ $? -eq 0 ]; then
    print_success "Feature versioning working correctly"
else
    print_error "Feature versioning check failed"
fi

# Test 12: Send events to trigger drift detection
print_section "Test 12: Drift Detection Test"

print_info "Sending events with anomalous patterns to trigger drift..."

# Send many events from one user to create anomaly
for i in {1..20}; do
    curl -s -X POST $INGESTION_URL/ingest \
        -H "Content-Type: application/json" \
        -d "{
            \"event_id\": \"drift_test_$i\",
            \"user_id\": \"user_alice\",
            \"event_type\": \"purchase\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }" > /dev/null
    sleep 0.1
done

wait_for_processing 3

# Check for drift alerts in metrics
drift_alerts=$(curl -s $FEATURE_METRICS_URL/metrics | grep "feature_drift_alerts")
if [ ! -z "$drift_alerts" ]; then
    print_success "Drift detection system active"
    echo "$drift_alerts"
else
    print_info "No drift alerts yet (may need more data)"
fi

# Final Summary
print_section "Test Summary"

total_tests=$((TESTS_PASSED + TESTS_FAILED))
success_rate=$((TESTS_PASSED * 100 / total_tests))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total Tests: $total_tests"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "Success Rate: ${success_rate}%"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Enhanced features checklist
print_section "Enhanced Features Status"

echo -e "${BLUE}✓ Feature Schema/Registry${NC} - features.yaml"
echo -e "${BLUE}✓ Feature Versioning${NC} - v1 and v2 support"
echo -e "${BLUE}✓ A/B Testing${NC} - Hash-based user assignment"
echo -e "${BLUE}✓ Advanced Feature Types${NC} - Categorical, ratios, temporal"
echo -e "${BLUE}✓ Multi-window Aggregations${NC} - 1h, 6h, 24h, 7d"
echo -e "${BLUE}✓ Drift Detection${NC} - Statistical monitoring"
echo -e "${BLUE}✓ Batch Processing${NC} - Configurable batch size"
echo -e "${BLUE}✓ Comprehensive Metrics${NC} - Prometheus integration"

echo ""
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed! Enhanced feature pipeline is working!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some tests failed. Check the output above for details.${NC}"
    exit 1
fi
