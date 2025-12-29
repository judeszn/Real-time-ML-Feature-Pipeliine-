#!/usr/bin/env python3
"""Simple consumer example that reads from `raw-events` and prints the JSON payload.
Run locally (if Kafka reachable at localhost:9092) or inside a container with networking to Kafka.
"""
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    "raw-events",
    bootstrap_servers=["localhost:9092"],
    auto_offset_reset="earliest",
    group_id="example-group",
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
)

print("Listening for messages on topic 'raw-events'... Ctrl+C to exit")
for msg in consumer:
    print(msg.value)
