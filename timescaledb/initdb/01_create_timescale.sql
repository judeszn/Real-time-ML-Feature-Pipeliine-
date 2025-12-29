-- Enable TimescaleDB extension on DB created by docker-entrypoint
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
-- Add any schema / initial tables for your pipeline here
