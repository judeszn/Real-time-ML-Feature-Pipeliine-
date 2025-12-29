# Monitoring & Infrastructure Setup

This Docker Compose configuration provisions a complete local ML feature pipeline infrastructure stack.

## Services

### Data Ingestion & Streaming
- **Kafka** (port 9092): Distributed event streaming platform
- **Zookeeper** (port 2181): Kafka coordination & metadata
- **Kafka UI** (port 8080): Web UI for Kafka monitoring & topic management

### Data Storage
- **TimescaleDB** (port 5432): PostgreSQL + TimescaleDB extension for time-series data
- **Redis** (port 6379): In-memory cache and data store

### Monitoring & Observability
- **Prometheus** (port 9090): Metrics collection & scraping
- **Grafana** (port 3000): Visualization and dashboarding (user: `admin`, default password: `admin`)
- **Exporters**:
  - `postgres_exporter`: Postgres/TimescaleDB metrics
  - `redis_exporter`: Redis metrics
  - `kafka_exporter`: Kafka broker metrics

## Quick Start

### Prerequisites
- Docker & Docker Compose installed
- 4GB+ available memory recommended

### Start the Stack
```bash
chmod +x scripts/*.sh
./scripts/start.sh
```

Or manually:
```bash
docker compose up -d
```

### Stop the Stack
```bash
./scripts/stop.sh
```

Or manually:
```bash
docker compose down
```

### Restart the Stack
```bash
./scripts/restart.sh
```

## Accessing Services

| Service | URL/Port |
|---------|----------|
| Kafka | `localhost:9092` |
| Zookeeper | `localhost:2181` |
| Kafka UI | `http://localhost:8080` |
| TimescaleDB | `localhost:5432` |
| Redis | `localhost:6379` |
| Prometheus | `http://localhost:9090` |
| Grafana | `http://localhost:3000` |

## Configuration

### Environment Variables
Edit `.env` to change:
- `POSTGRES_PASSWORD` — TimescaleDB password
- `POSTGRES_USER` — TimescaleDB user
- `GF_SECURITY_ADMIN_PASSWORD` — Grafana admin password

### TimescaleDB Initialization
SQL scripts in `timescaledb/initdb/` run automatically on first container start.
- Enables `timescaledb` extension
- Add custom schemas/tables here

### Prometheus
Scrape targets configured in `prometheus/prometheus.yml`:
- Prometheus itself
- Postgres exporter
- Redis exporter
- Kafka exporter

### Grafana
Provisioning files in `grafana/provisioning/`:
- `datasources/datasource.yml` — Prometheus data source
- `dashboards/dashboards.yml` — Dashboard provisioning
- Add JSON dashboard files to `grafana/dashboards/` for auto-loading

## Common Tasks

### View Service Logs
```bash
docker compose logs -f <service>
# Example: docker compose logs -f kafka
```

### Check Service Health
```bash
docker compose ps
```

### Connect to TimescaleDB
```bash
psql -h localhost -U postgres -d postgres
```

### Publish to Kafka
```bash
docker exec -it <project>-kafka-1 \
  kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic <topic-name>
```

### Monitor Grafana
1. Visit `http://localhost:3000`
2. Login as `admin` with your password from `.env`
3. Prometheus data source should be auto-configured
4. Add dashboards by importing JSON files

## Troubleshooting

### Services Failing to Start
- Check Docker daemon: `docker ps`
- View logs: `docker compose logs <service>`
- Ensure ports are not in use: `lsof -i :<port>`

### Metrics Not Appearing
- Verify exporters are running: `docker compose ps`
- Check Prometheus targets: `http://localhost:9090/targets`
- Wait 30s for initial scrapes

### Database Connection Issues
- Verify TimescaleDB is healthy: `docker compose ps timescaledb`
- Check password in `.env` matches env var usage
- Connection string: `postgresql://postgres:PASSWORD@localhost:5432/postgres`

## Project Structure
```
.
├── docker-compose.yml              # Main service definitions
├── .env                            # Credentials & configuration
├── prometheus/
│   └── prometheus.yml              # Prometheus scrape config
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/datasource.yml
│   │   └── dashboards/dashboards.yml
│   └── dashboards/                 # Place JSON dashboards here
├── timescaledb/
│   └── initdb/
│       └── 01_create_timescale.sql # TimescaleDB init script
└── scripts/
    ├── start.sh                    # Start stack
    ├── stop.sh                     # Stop stack
    └── restart.sh                  # Restart stack
```

## Next Steps

1. **Add data producers** — Create Kafka producers to emit feature data
2. **Build dashboards** — Import or create Grafana dashboards for your metrics
3. **Set up alerting** — Configure Prometheus alert rules and Grafana notifications
4. **Integrate ML pipeline** — Connect your ML code to read from Kafka/Redis and write to TimescaleDB
5. **Optimize retention** — Set up TimescaleDB data retention policies

## Topic strategy & examples

**Topic strategy (recommended):**
- `raw-events` — Raw incoming events (no processing)
- `processed-events` — Cleaned and validated events
- `feature-events` — Computed features ready for ML models
- `dead-letter-queue` — Failed events for debugging

### Create topics (script)
A helper script is provided to create these topics with sensible defaults.

```bash
chmod +x scripts/create-kafka-topics.sh
./scripts/create-kafka-topics.sh
```

### Example producer & consumer (Python)
- `examples/producer.py` — sends sample JSON messages to `raw-events`.
- `examples/consumer.py` — consumes messages from `raw-events` and prints them.

Notes & tips:
- If Kafka is not reachable from your host (common if advertised listeners are internal), either run the producer inside the Kafka container with `docker compose exec kafka` or update `KAFKA_CFG_ADVERTISED_LISTENERS` in `docker-compose.yml` to advertise a host-reachable address (e.g., `PLAINTEXT://localhost:9092`).
- For production: add Schema Registry and use Avro/Protobuf to enforce strict schemas.
- Consider `cleanup.policy=compact` for topics that store latest-key state (e.g., lookup tables) and retention settings for raw event topics.


## Notes

- All services use a shared `monitoring` Docker network for communication
- Volumes are persistent: data survives container restarts
- Default credentials (Postgres, Grafana) should be changed in production
- Healthchecks are configured; services wait for dependencies
