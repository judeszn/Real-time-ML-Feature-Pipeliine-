#!/bin/bash
set -e

echo "Starting infrastructure stack..."
docker compose up -d

echo "Waiting for services to be healthy..."
sleep 10

echo "Checking service status..."
docker compose ps

echo ""
echo "Infrastructure ready!"
echo ""
echo "Service endpoints:"
echo "  Kafka:        localhost:9092"
echo "  Zookeeper:    localhost:2181"
echo "  Kafka UI:     http://localhost:8080"
echo "  TimescaleDB:  localhost:5432 (user: postgres)"
echo "  Redis:        localhost:6379"
echo "  Prometheus:   http://localhost:9090"
echo "  Grafana:      http://localhost:3000 (admin/admin)"
echo ""
echo "Useful commands:"
echo "  docker compose logs -f <service>"
echo "  docker compose ps"
echo "  docker compose down"
