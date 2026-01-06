#!/bin/bash
# Wait for Docker build to complete and start services

echo "Waiting for Docker build to complete..."
echo "This may take 3-5 minutes..."

# Poll for build completion
while docker-compose build 2>&1 | grep -q "Building\|RUN"; do
    echo "Still building... ($(date +%H:%M:%S))"
    sleep 10
done

echo "Build complete!"

# Start services
echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting 30 seconds for services to initialize..."
sleep 30

# Check status
echo ""
echo "Service Status:"
docker-compose ps

echo ""
echo "✅ Services starting up!"
echo ""
echo "Access Points:"
echo "  • Ingestion API: http://localhost:8081"
echo "  • Feature API:   http://localhost:8083"
echo "  • Kafka UI:      http://localhost:8080"
echo "  • Grafana:       http://localhost:3000"
echo "  • Prometheus:    http://localhost:9090"
echo ""
echo "Test with:"
echo "  ./test-phase3.sh"
