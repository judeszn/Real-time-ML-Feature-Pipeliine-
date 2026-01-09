FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir requests

# Copy simulator
COPY main.py .

# Default: 5 users, 10 events/min, continuous
CMD ["python", "main.py", "--url", "http://ingestion-service:8081/events", "--users", "5", "--events-per-minute", "10"]
