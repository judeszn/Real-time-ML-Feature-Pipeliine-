# Docker Compose — Dev Infra

This workspace contains a local development `docker-compose.yml` that brings up:
- Kafka + Zookeeper
- TimescaleDB (Postgres + TimescaleDB extension)
- Redis
- Kafka-UI
- Prometheus + Grafana
- Exporters: Postgres exporter, Redis exporter, Kafka exporter

Quick start

1. Build and start:

   docker compose up -d

2. Useful ports
- Kafka: 9092
- Zookeeper: 2181
- TimescaleDB: 5432
- Redis: 6379
- Kafka UI: 8080
- Prometheus: 9090
- Grafana: 3000 (admin/admin)

Notes
- TimescaleDB init scripts live in `timescaledb/initdb` and are applied on first container start.
- Prometheus config is at `prometheus/prometheus.yml`.
- Grafana provisioning files are in `grafana/provisioning`.
- You may want to tune advertised listeners for Kafka if you need to connect from host/native clients.

Next steps
- Add healthchecks and improve env vars (timeouts, passwords in `.env`).
- Add dashboard JSONs for Kafka/Postgres/Redis.
- Run `docker compose up` and test connectivity.
