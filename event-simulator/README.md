# 🛍️ Shopping Store Event Simulator

Generates realistic e-commerce events to feed your ML feature pipeline. Perfect for testing, demos, and load testing.

## What It Does

- **Simulates shopping user behavior**: login → browse → cart → purchase → logout
- **Realistic events**: 11 different shopping actions (login, view, add_to_cart, purchase, etc.)
- **Real products**: Electronics, clothing, books with actual prices
- **Concurrent users**: Run multiple users simultaneously
- **Configurable**: Control event rate, user count, and test duration

## Quick Start (Local)

```bash
# Terminal 1: Start full stack
./start-full-stack.sh

# Terminal 2: Run simulator (continuous)
docker compose up event-simulator

# Terminal 3: Watch features being computed
watch -n 2 'curl -s http://localhost:8084/features/user_1 | jq ".features | length"'
```

## Usage

### Run Locally (without Docker)

```bash
# Install dependencies
pip install requests

# Run continuous simulation
python event-simulator/main.py \
  --url http://localhost:8085/events \
  --users 5 \
  --events-per-minute 10

# Or run a load test
python event-simulator/main.py \
  --url http://localhost:8085/events \
  --load-test 50 \
  --duration 60
```

### Run in Docker Compose

```bash
# Start simulator with full stack
docker compose up -d event-simulator

# View logs
docker compose logs -f event-simulator

# Stop simulator
docker compose stop event-simulator
```

### Run in Kubernetes

```bash
# Build and push image
docker build -t $ECR_REGISTRY/event-simulator:latest ./event-simulator
docker push $ECR_REGISTRY/event-simulator:latest

# Update k8s/event-simulator-deployment.yaml with image URI

# Deploy
kubectl apply -f k8s/event-simulator-deployment.yaml

# View logs
kubectl logs -f -n ml-pipeline deployment/event-simulator
```

## Command Line Options

```bash
python event-simulator/main.py --help

Options:
  --url URL                    Ingestion service URL
                              (default: http://localhost:8085/events)
  
  --users N                   Number of concurrent users
                              (default: 5)
  
  --events-per-minute N       Target events per minute
                              (default: 10)
  
  --load-test N              Run load test with N concurrent users
                             (overrides normal mode)
  
  --duration SECONDS         Stop after N seconds
                             (default: run forever)
```

## Examples

### Continuous Simulation with Default Settings
```bash
python event-simulator/main.py
# 5 users, ~10 events/min, runs forever
```

### High-Volume Testing
```bash
python event-simulator/main.py \
  --users 50 \
  --events-per-minute 100
# 50 concurrent users, ~100 events/min
```

### Load Test (50 concurrent users for 5 minutes)
```bash
python event-simulator/main.py \
  --load-test 50 \
  --duration 300
```

### Custom Endpoint
```bash
python event-simulator/main.py \
  --url http://your-api.example.com/events \
  --users 10
```

## Event Types

The simulator generates these realistic shopping events:

| Event | Context | Example Data |
|-------|---------|--------------|
| **login** | User starts session | timestamp |
| **view** | User views product | product, category, price |
| **add_to_cart** | User adds item | product, quantity |
| **remove_from_cart** | User removes item | product |
| **purchase** | User buys items | product, quantity |
| **logout** | User ends session | timestamp |

## Generated Features

The pipeline computes these features from events:

- **activity_count_1h/6h/24h/7d**: Events in time windows
- **activity_trend**: User engagement trend
- **event_type_frequency_24h**: Breakdown by event type
- **seconds_since_last_event**: Time since last activity
- **is_active_session**: Boolean, activity in last 30 min
- **engagement_score**: Composite user engagement metric
- **day_of_week/hour_of_day**: Temporal features
- **device_type_***: Device information
- **payment_method_***: Payment patterns

## Monitoring

### View Real-Time Events

```bash
# Check Kafka messages
docker compose exec -T kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic raw-events \
  --from-beginning \
  --max-messages 20

# Count messages per topic
docker compose exec -T kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group feature-computation-group-v2 \
  --describe
```

### Check Computed Features

```bash
# Query latest features
curl http://localhost:8084/features/user_1 | jq

# Check database directly
docker compose exec -T postgres psql \
  -U admin -d featurestore \
  -c "SELECT user_id, COUNT(*) as feature_count, MAX(computed_at) as latest FROM features GROUP BY user_id;"
```

### Monitor Simulator Performance

```bash
# Check container stats
docker stats real-time-ml-feature-pipeline-event-simulator-1

# View detailed logs
docker compose logs event-simulator -f --tail 50
```

## Performance Tuning

### For Light Load
```bash
--users 5 --events-per-minute 10
# ~1 event per 300ms
# CPU: minimal, Memory: <100MB
```

### For Medium Load
```bash
--users 20 --events-per-minute 50
# ~1 event per 24ms
# CPU: moderate, Memory: ~200MB
```

### For Heavy Load / Stress Test
```bash
--load-test 100 --duration 300
# 100 concurrent users starting at once
# CPU: high, Memory: ~500MB
# Good for testing autoscaling

# Then deploy with HPA:
kubectl autoscale deployment ingestion-service \
  -n ml-pipeline \
  --min=2 --max=10 \
  --cpu-percent=70
```

## Kubernetes Deployment

The simulator is automatically deployed with K8s:

```yaml
# k8s/event-simulator-deployment.yaml
replicas: 1           # Scale up for more load
users: 10             # Users per simulator instance
events-per-minute: 30 # Total with multiple instances
```

### Scale for Load Testing

```bash
# Increase simulators
kubectl scale deployment event-simulator \
  -n ml-pipeline \
  --replicas 3

# Monitor feature processor scaling
kubectl get hpa -n ml-pipeline -w

# Check resource usage
kubectl top pods -n ml-pipeline
```

## Troubleshooting

**Events not being sent?**
```bash
# Check if ingestion service is running
curl http://localhost:8085/health | jq

# Check simulator logs for errors
docker compose logs event-simulator | grep "Error"
```

**Features not computing?**
```bash
# Check processor logs
docker compose logs feature-processor | tail -50

# Verify Kafka messages are flowing
docker compose exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:29092 \
  --group feature-computation-group-v2 \
  --describe
```

**High memory usage?**
```bash
# Reduce user count
python event-simulator/main.py --users 5 --events-per-minute 5

# Or in Kubernetes
kubectl set env deployment/event-simulator \
  -n ml-pipeline \
  USERS=3 \
  EVENTS_PER_MINUTE=5
```

## Architecture

```
User Simulator (this tool)
    ↓ HTTP POST /events
Ingestion Service (Go)
    ↓ Kafka Producer (gzip)
Kafka Topic: raw-events
    ↓ Kafka Consumer
Feature Processor (Python)
    ↓ Write Features
PostgreSQL: features table
    ↓ API Query
Feature API (Flask)
    ← curl requests
```

## Cost Considerations

**Local Development**: Free (uses Docker)

**AWS Deployment**:
- Event Simulator Pod: ~$5/month (100m CPU)
- Ingestion Service: ~$20/month (scaled)
- Feature Processor: ~$20/month (scaled)
- Total additional: ~$50/month

**Reduce Costs**:
- Run simulator during business hours only
- Use spot instances for K8s nodes
- Scale down at night/weekends

## Integration with CI/CD

The simulator can be used in GitHub Actions workflows:

```yaml
# .github/workflows/load-test.yml
- name: Run load test
  run: |
    python event-simulator/main.py \
      --url http://localhost:8085/events \
      --load-test 50 \
      --duration 300
```

## Next Steps

1. **Local Testing**: Run simulator with docker compose
2. **AWS Deployment**: Push to ECR, deploy to EKS
3. **Load Testing**: Use `--load-test` option to stress test
4. **CI/CD Integration**: Add to GitHub Actions workflows
5. **Monitoring**: Set up CloudWatch alarms for event rates

---

**Questions?** Check [LEARNING_PATH.md](../LEARNING_PATH.md) for AWS/K8s tutorials, or [DEPLOY_TO_AWS.md](../DEPLOY_TO_AWS.md) for step-by-step AWS deployment.
