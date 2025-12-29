#!/bin/bash
set -e

echo "Stopping infrastructure stack..."
docker compose down
echo "Stack stopped"
