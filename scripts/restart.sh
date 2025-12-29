#!/bin/bash
set -e

echo "Restarting infrastructure stack..."
docker compose restart
echo "Stack restarted. Waiting for services..."
sleep 5
docker compose ps
