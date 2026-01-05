-- Enable TimescaleDB extension on DB created by docker-entrypoint
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Create raw events table
CREATE TABLE IF NOT EXISTS raw_events (
    id SERIAL,
    event_id VARCHAR(100) PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    device_type VARCHAR(20),
    metadata JSONB,
    ingested_at TIMESTAMPTZ DEFAULT NOW()
);

-- Convert to hypertable for time-series optimization
SELECT create_hypertable('raw_events', 'timestamp', if_not_exists => TRUE);

-- Create features table with versioning support
CREATE TABLE IF NOT EXISTS features (
    id SERIAL,
    user_id VARCHAR(100) NOT NULL,
    feature_name VARCHAR(100) NOT NULL,
    feature_value DOUBLE PRECISION,
    computed_at TIMESTAMPTZ NOT NULL,
    feature_version VARCHAR(20) DEFAULT 'v1',
    ab_variant VARCHAR(10) DEFAULT 'A',
    PRIMARY KEY (user_id, feature_name)
);

-- Create index for faster feature lookups
CREATE INDEX IF NOT EXISTS idx_features_user_id ON features(user_id);
CREATE INDEX IF NOT EXISTS idx_features_computed_at ON features(computed_at DESC);
CREATE INDEX IF NOT EXISTS idx_features_version ON features(feature_version);
CREATE INDEX IF NOT EXISTS idx_features_variant ON features(ab_variant);

-- Create feature history table for tracking changes over time
CREATE TABLE IF NOT EXISTS feature_history (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    feature_name VARCHAR(100) NOT NULL,
    feature_value DOUBLE PRECISION,
    computed_at TIMESTAMPTZ NOT NULL,
    feature_version VARCHAR(20),
    ab_variant VARCHAR(10)
);

-- Convert to hypertable for time-series optimization
SELECT create_hypertable('feature_history', 'computed_at', if_not_exists => TRUE);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_feature_history_user ON feature_history(user_id, feature_name, computed_at DESC);

-- Create drift alerts table
CREATE TABLE IF NOT EXISTS drift_alerts (
    id SERIAL PRIMARY KEY,
    feature_name VARCHAR(100) NOT NULL,
    alert_type VARCHAR(50) NOT NULL,
    baseline_mean DOUBLE PRECISION,
    current_mean DOUBLE PRECISION,
    baseline_std DOUBLE PRECISION,
    current_std DOUBLE PRECISION,
    mean_shift DOUBLE PRECISION,
    std_shift DOUBLE PRECISION,
    detected_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for drift alerts
CREATE INDEX IF NOT EXISTS idx_drift_alerts_feature ON drift_alerts(feature_name, detected_at DESC);

-- Create view for latest features per user
CREATE OR REPLACE VIEW latest_features AS
SELECT DISTINCT ON (user_id, feature_name)
    user_id,
    feature_name,
    feature_value,
    computed_at,
    feature_version,
    ab_variant
FROM features
ORDER BY user_id, feature_name, computed_at DESC;

-- Create view for feature statistics
CREATE OR REPLACE VIEW feature_stats AS
SELECT 
    feature_name,
    feature_version,
    ab_variant,
    COUNT(*) as user_count,
    AVG(feature_value) as mean_value,
    STDDEV(feature_value) as std_value,
    MIN(feature_value) as min_value,
    MAX(feature_value) as max_value,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY feature_value) as median_value
FROM features
GROUP BY feature_name, feature_version, ab_variant;

-- Grant permissions (if needed)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO your_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO your_user;

