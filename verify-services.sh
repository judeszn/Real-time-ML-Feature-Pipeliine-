#!/bin/bash
echo "=== SERVICE VERIFICATION ==="
echo ""

echo "1. Checking container status..."
docker-compose ps

echo ""
echo "2. Testing Kafka..."
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null && echo "Kafka OK" || echo "Kafka FAILED"

echo ""
echo "3. Testing PostgreSQL..."
docker-compose exec postgres pg_isready -U admin 2>/dev/null && echo "PostgreSQL OK" || echo "PostgreSQL FAILED"

echo ""
echo "4. Testing Redis..."
docker-compose exec redis redis-cli ping 2>/dev/null | grep -q PONG && echo "Redis OK" || echo "Redis FAILED"

echo ""
echo "5. Testing Prometheus..."
curl -s http://localhost:9090/-/healthy 2>/dev/null | grep -q "Prometheus" && echo "Prometheus OK" || echo "Prometheus FAILED"

echo ""
echo "6. Testing Grafana..."
curl -s http://localhost:3000/api/health 2>/dev/null | grep -q "ok" && echo "Grafana OK" || echo "Grafana FAILED"

echo ""
echo "7. Testing Kafka UI..."
curl -s -I http://localhost:8080 2>/dev/null | grep -q "200" && echo "Kafka UI OK" || echo "Kafka UI FAILED"

echo ""
echo "=== ACCESS URLs ==="
echo "Kafka UI:      http://localhost:8080"
echo "Grafana:       http://localhost:3000 (admin/admin)"
echo "Prometheus:    http://localhost:9090"
echo "PostgreSQL:    localhost:5432 (featurestore/admin/<password from .env>)"
echo "Redis:         localhost:6379"
echo "Kafka:         localhost:9092"
