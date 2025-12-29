#!/bin/bash
echo "=== ML PIPELINE INFRASTRUCTURE VERIFIED ==="
echo ""

echo "📊 SERVICE STATUS:"
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "📈 KAFKA TOPICS:"
docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092 | grep -v "__consumer_offsets"
echo ""

echo "🗄️  DATABASE TABLES:"
docker-compose exec postgres psql -U admin -d featurestore -c "\dt"
echo ""

echo "🔢 DATABASE ROW COUNT:"
docker-compose exec postgres psql -U admin -d featurestore -c "SELECT 'raw_events' as table, COUNT(*) as count FROM raw_events UNION ALL SELECT 'features' as table, COUNT(*) as count FROM features;"
echo ""

echo "⚡ REDIS TEST:"
docker-compose exec redis redis-cli ping
echo ""

echo "🌐 WEB INTERFACES:"
echo "   Kafka UI:      http://localhost:8080"
echo "   Grafana:       http://localhost:3000 (admin/admin)"
echo "   Prometheus:    http://localhost:9090"
echo ""
echo "🔌 CONNECTION STRINGS:"
echo "   Kafka:         localhost:9092"
echo "   PostgreSQL:    localhost:5432/featurestore (user: admin, password: admin123)"
echo "   Redis:         localhost:6379"
echo ""
echo "✅ INFRASTRUCTURE PHASE COMPLETE!"
echo ""
echo "=== NEXT: BUILD SERVICES ==="
echo "1. Go Ingestion Service (HTTP API → Kafka)"
echo "2. Python Processing Service (Kafka → Features)"
echo "3. Feature Store API (Serve features to ML models)"
