#!/bin/bash
set -euo pipefail

echo "Building images (one pass)..."
docker compose build --parallel

echo "Starting services..."
docker compose up -d

echo "Waiting 30 seconds for services to initialize..."
sleep 30

echo "Service Status:"
docker compose ps

echo ""
echo "✅ Services started. Access Points:"
echo "  • Ingestion API: http://localhost:8085"
echo "  • Feature API:   http://localhost:8084"
echo "  • Feature metrics: http://localhost:8086/metrics"
echo "  • Kafka UI:      http://localhost:8080"
echo "  • Grafana:       http://localhost:3030"
echo "  • Prometheus:    http://localhost:9090"
echo "  • Postgres:      localhost:5434 (inside: postgres:5432)"
echo "  • Kafka broker:  kafka:29092 (inside), localhost:9092 (host)"
echo ""
echo "Test with:"
echo "  ./test-phase3.sh"
