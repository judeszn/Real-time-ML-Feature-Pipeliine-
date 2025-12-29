#!/usr/bin/env python3
"""Simple producer example that sends JSON messages to `raw-events` topic.
Run locally (if Kafka reachable at localhost:9092) or inside a container with networking to Kafka.
"""
from kafka import KafkaProducer
import json
import time

producer = KafkaProducer(
    bootstrap_servers=["localhost:9092"],
    value_serializer=lambda v: json.dumps(v).encode("utf-8"),
)

for i in range(10):
    payload = {"id": i, "value": i * 0.1, "ts": time.time()}
    producer.send("raw-events", value=payload)
    print("sent", payload)
    time.sleep(1)

producer.flush()
