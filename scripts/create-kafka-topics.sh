#!/usr/bin/env bash


set -euo pipefail

# Create the standard topics for the ML feature pipeline
# Run from the repository root: chmod +x scripts/create-kafka-topics.sh && ./scripts/create-kafka-topics.sh

topics=(raw-events processed-events feature-events dead-letter-queue)
for t in "${topics[@]}"; do
  echo "Creating topic: $t"
  docker compose exec kafka kafka-topics.sh --create --topic "$t" \
    --bootstrap-server localhost:9092 \
    --partitions 3 \
    --replication-factor 1 || true
done

echo "Current topics:"
docker compose exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092
