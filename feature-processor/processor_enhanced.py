import json
import logging
import os
import signal
import sys
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from collections import defaultdict
import hashlib

import yaml
from kafka import KafkaConsumer, KafkaProducer
import redis
import psycopg2
from psycopg2.extras import execute_values
from prometheus_client import Counter, Histogram, Gauge, Summary, start_http_server

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
EVENTS_PROCESSED = Counter('events_processed_total', 'Total events processed')
EVENTS_FAILED = Counter('events_failed_total', 'Total events failed')
FEATURE_COMPUTATION_TIME = Histogram('feature_computation_seconds', 'Time to compute features')
CONSUMER_LAG = Gauge('kafka_consumer_lag', 'Consumer lag behind latest offset')
CACHE_HITS = Counter('cache_hits_total', 'Total cache hits')
CACHE_MISSES = Counter('cache_misses_total', 'Total cache misses')
BATCH_SIZE = Histogram('batch_size', 'Number of events in batch')
FEATURE_VALUE_DISTRIBUTION = Summary(
    'feature_value_distribution',
    'Distribution of feature values',
    ['feature_name']
)
AB_VARIANT_COUNTER = Counter('ab_variant_assignments', 'A/B variant assignments', ['variant'])
DRIFT_ALERTS = Counter('feature_drift_alerts', 'Feature drift alerts triggered', ['feature_name'])


class FeatureRegistry:
    """Load and manage feature definitions from YAML"""
    
    def __init__(self, config_path: str = 'features.yaml'):
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.version = self.config.get('feature_version', 'v1')
        self.features = self.config.get('features', {})
        self.cache_config = self.config.get('cache', {})
        self.ab_config = self.config.get('ab_testing', {})
        self.drift_config = self.config.get('drift_detection', {})
        
        logger.info(f"Loaded feature registry version: {self.version}")
        logger.info(f"A/B testing enabled: {self.ab_config.get('enabled', False)}")
        logger.info(f"Drift detection enabled: {self.drift_config.get('enabled', False)}")
    
    def get_feature_ttl(self, feature_name: str) -> int:
        """Get cache TTL for a specific feature"""
        ttls = self.cache_config.get('feature_ttls', {})
        return ttls.get(feature_name, self.cache_config.get('default_ttl_seconds', 300))
    
    def get_user_variant(self, user_id: str) -> str:
        """Determine A/B test variant for user (deterministic hash-based)"""
        if not self.ab_config.get('enabled', False):
            return 'A'
        
        # Hash user_id to assign consistent variant
        hash_value = int(hashlib.md5(user_id.encode()).hexdigest(), 16)
        variant_percentage = hash_value % 100
        
        variants = self.ab_config.get('variants', [])
        cumulative = 0
        for variant in variants:
            cumulative += variant.get('traffic_percentage', 50)
            if variant_percentage < cumulative:
                return variant.get('id', 'A')
        
        return 'A'
    
    def should_compute_feature(self, feature_name: str, variant: str) -> bool:
        """Check if feature should be computed for given variant"""
        # Map variant to version
        for var in self.ab_config.get('variants', []):
            if var.get('id') == variant:
                version = var.get('features_version', 'v1')
                # Check if feature exists in this version
                for category in self.features.values():
                    for feature in category:
                        if feature.get('name') == feature_name:
                            return feature.get('version', 'v1') == version or version == 'v2'
        return True


class DriftDetector:
    """Monitor feature distributions and detect drift"""
    
    def __init__(self, redis_client, config: Dict):
        self.redis_client = redis_client
        self.config = config
        self.enabled = config.get('enabled', False)
        self.thresholds = config.get('thresholds', {})
        
    def record_feature_value(self, feature_name: str, value: float):
        """Record feature value for drift monitoring"""
        if not self.enabled or value is None:
            return
        
        # Store in Redis sorted set with timestamp
        key = f"drift:values:{feature_name}"
        timestamp = datetime.utcnow().timestamp()
        self.redis_client.zadd(key, {f"{timestamp}:{value}": timestamp})
        
        # Keep only last hour of data
        cutoff = timestamp - 3600
        self.redis_client.zremrangebyscore(key, '-inf', cutoff)
        
        # Update rolling statistics
        self._update_statistics(feature_name, value)
        
        # Check for drift
        self._check_drift(feature_name)
    
    def _update_statistics(self, feature_name: str, value: float):
        """Update rolling mean and std"""
        stats_key = f"drift:stats:{feature_name}"
        
        # Get current stats
        stats = self.redis_client.hgetall(stats_key)
        count = int(stats.get('count', 0))
        mean = float(stats.get('mean', 0))
        m2 = float(stats.get('m2', 0))  # For Welford's algorithm
        
        # Update using Welford's online algorithm
        count += 1
        delta = value - mean
        mean += delta / count
        delta2 = value - mean
        m2 += delta * delta2
        
        # Store updated stats
        self.redis_client.hset(stats_key, mapping={
            'count': count,
            'mean': mean,
            'm2': m2,
            'std': (m2 / count) ** 0.5 if count > 1 else 0
        })
        self.redis_client.expire(stats_key, 3600)
    
    def _check_drift(self, feature_name: str):
        """Check if feature has drifted beyond threshold"""
        if feature_name not in self.thresholds:
            return
        
        # Get baseline (from 1 hour ago)
        baseline_key = f"drift:baseline:{feature_name}"
        baseline = self.redis_client.hgetall(baseline_key)
        
        if not baseline:
            # Initialize baseline
            stats_key = f"drift:stats:{feature_name}"
            stats = self.redis_client.hgetall(stats_key)
            if stats:
                self.redis_client.hset(baseline_key, mapping=stats)
                self.redis_client.expire(baseline_key, 3600)
            return
        
        # Compare current stats to baseline
        current_key = f"drift:stats:{feature_name}"
        current = self.redis_client.hgetall(current_key)
        
        if not current:
            return
        
        baseline_mean = float(baseline.get('mean', 0))
        current_mean = float(current.get('mean', 0))
        baseline_std = float(baseline.get('std', 1))
        current_std = float(current.get('std', 1))
        
        thresholds = self.thresholds[feature_name]
        mean_shift_threshold = thresholds.get('mean_shift', 10.0)
        std_shift_threshold = thresholds.get('std_shift', 5.0)
        
        # Check mean shift
        mean_shift = abs(current_mean - baseline_mean)
        std_shift = abs(current_std - baseline_std)
        
        if mean_shift > mean_shift_threshold or std_shift > std_shift_threshold:
            logger.warning(
                f"DRIFT DETECTED for {feature_name}: "
                f"mean_shift={mean_shift:.2f}, std_shift={std_shift:.2f}"
            )
            DRIFT_ALERTS.labels(feature_name=feature_name).inc()


class EnhancedFeatureProcessor:
    def __init__(self):
        # Load feature registry
        self.registry = FeatureRegistry()
        
        # Kafka configuration
        self.kafka_brokers = os.getenv('KAFKA_BROKERS', 'kafka:9092').split(',')
        self.consumer_group = os.getenv('CONSUMER_GROUP', 'feature-computation-group')
        
        # Database configuration
        self.db_config = {
            'host': os.getenv('POSTGRES_HOST', 'timescaledb'),
            'port': int(os.getenv('POSTGRES_PORT', '5432')),
            'database': os.getenv('POSTGRES_DB', 'featurestore'),
            'user': os.getenv('POSTGRES_USER', 'postgres'),
            'password': os.getenv('POSTGRES_PASSWORD', 'postgres')
        }
        
        # Redis configuration
        self.redis_client = redis.Redis(
            host=os.getenv('REDIS_HOST', 'redis'),
            port=int(os.getenv('REDIS_PORT', '6379')),
            db=0,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_keepalive=True,
            max_connections=50
        )
        
        # Drift detector
        self.drift_detector = DriftDetector(self.redis_client, self.registry.drift_config)
        
        # Initialize connections
        self.consumer = None
        self.producer = None
        self.db_conn = None
        self.running = True
        
        # Batch processing
        self.batch = []
        self.batch_size = int(os.getenv('BATCH_SIZE', '100'))
        self.batch_timeout = float(os.getenv('BATCH_TIMEOUT', '1.0'))
        self.last_batch_time = datetime.utcnow()
        
    def connect(self):
        """Initialize all connections"""
        try:
            # Kafka consumer with optimized settings
            self.consumer = KafkaConsumer(
                'raw-events',
                bootstrap_servers=self.kafka_brokers,
                group_id=self.consumer_group,
                auto_offset_reset='earliest',
                enable_auto_commit=True,
                auto_commit_interval_ms=5000,
                max_poll_records=500,
                max_poll_interval_ms=300000,
                session_timeout_ms=30000,
                value_deserializer=lambda m: json.loads(m.decode('utf-8'))
            )
            
            # Kafka producer for feature events
            self.producer = KafkaProducer(
                bootstrap_servers=self.kafka_brokers,
                acks=1,
                compression_type='snappy',
                linger_ms=10,
                batch_size=16384,
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            
            # Database connection
            self.db_conn = psycopg2.connect(**self.db_config)
            self.db_conn.autocommit = False
            
            # Test Redis connection
            self.redis_client.ping()
            
            logger.info("All connections established successfully")
            
        except Exception as e:
            logger.error(f"Failed to establish connections: {e}")
            raise
    
    def compute_temporal_features(self, event: Dict[str, Any], variant: str) -> Dict[str, Any]:
        """Compute time-based features"""
        features = {}
        timestamp = event.get('ingested_at', datetime.utcnow().isoformat())
        
        try:
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            
            if self.registry.should_compute_feature('hour_of_day', variant):
                features['hour_of_day'] = dt.hour
            
            if self.registry.should_compute_feature('day_of_week', variant):
                features['day_of_week'] = dt.weekday()
            
            if self.registry.should_compute_feature('is_weekend', variant):
                features['is_weekend'] = dt.weekday() >= 5
                
        except Exception as e:
            logger.error(f"Error computing temporal features: {e}")
        
        return features
    
    def compute_categorical_features(self, event: Dict[str, Any], variant: str) -> Dict[str, Any]:
        """Compute one-hot encoded categorical features"""
        features = {}
        event_type = event.get('event_type', 'unknown')
        
        if self.registry.should_compute_feature('event_type_encoded', variant):
            # One-hot encoding for event types
            event_types = ['login', 'logout', 'purchase', 'view', 'click', 'search']
            for et in event_types:
                features[f'event_type_{et}'] = 1 if event_type == et else 0
        
        # Device type encoding (if present in event)
        device = event.get('device_type', 'unknown')
        if self.registry.should_compute_feature('device_type_encoded', variant):
            device_types = ['mobile', 'desktop', 'tablet']
            for dt in device_types:
                features[f'device_type_{dt}'] = 1 if device == dt else 0
        
        return features
    
    def compute_windowed_aggregations(self, user_id: str, event_type: str, variant: str) -> Dict[str, Any]:
        """Compute features over multiple time windows"""
        features = {}
        
        # Multiple window sizes (1h, 6h, 24h, 7d)
        windows = {
            'activity_count_1h': 3600,
            'activity_count_6h': 21600,
            'activity_count_24h': 86400,
            'activity_count_7d': 604800
        }
        
        for feature_name, window_seconds in windows.items():
            if not self.registry.should_compute_feature(feature_name, variant):
                continue
                
            cache_key = f"activity:{user_id}:{window_seconds}"
            cached_count = self.redis_client.get(cache_key)
            
            if cached_count:
                CACHE_HITS.inc()
                features[feature_name] = int(cached_count) + 1
            else:
                CACHE_MISSES.inc()
                count = self._get_activity_count_from_db(user_id, window_seconds // 3600) + 1
                features[feature_name] = count
            
            # Update cache
            ttl = self.registry.get_feature_ttl(feature_name)
            self.redis_client.setex(cache_key, ttl, features[feature_name])
        
        # Event type frequency
        if self.registry.should_compute_feature('event_type_frequency_24h', variant):
            event_freq_key = f"event_freq:{user_id}:{event_type}:24h"
            self.redis_client.incr(event_freq_key)
            self.redis_client.expire(event_freq_key, 86400)
            features['event_type_frequency_24h'] = int(self.redis_client.get(event_freq_key) or 0)
        
        return features
    
    def compute_ratio_features(self, user_id: str, features: Dict[str, Any], variant: str) -> Dict[str, Any]:
        """Compute ratio-based derived features"""
        ratio_features = {}
        
        # Activity trend (1h / 24h)
        if self.registry.should_compute_feature('activity_trend', variant):
            count_1h = features.get('activity_count_1h', 0)
            count_24h = features.get('activity_count_24h', 1)
            ratio_features['activity_trend'] = count_1h / max(count_24h, 1)
        
        # Purchase rate (requires tracking purchase vs view events)
        if self.registry.should_compute_feature('purchase_rate_24h', variant):
            purchase_key = f"event_freq:{user_id}:purchase:24h"
            view_key = f"event_freq:{user_id}:view:24h"
            
            purchases = int(self.redis_client.get(purchase_key) or 0)
            views = int(self.redis_client.get(view_key) or 0)
            
            ratio_features['purchase_rate_24h'] = purchases / max(views, 1)
        
        return ratio_features
    
    def compute_engagement_score(self, features: Dict[str, Any], variant: str) -> float:
        """Compute composite engagement score based on variant"""
        
        if variant == 'B' and self.registry.should_compute_feature('engagement_score_v2', variant):
            # Enhanced v2 algorithm
            score = 0
            
            # Activity component (40 points)
            count_1h = features.get('activity_count_1h', 0)
            count_24h = features.get('activity_count_24h', 0)
            if count_24h > 20:
                score += 40
            elif count_24h > 10:
                score += 30
            elif count_24h > 5:
                score += 20
            elif count_1h > 0:
                score += 10
            
            # Session component (20 points)
            if features.get('is_active_session', False):
                score += 20
            
            # Trend component (20 points)
            trend = features.get('activity_trend', 0)
            if trend > 0.5:
                score += 20
            elif trend > 0.2:
                score += 10
            
            # Purchase behavior (20 points)
            purchase_rate = features.get('purchase_rate_24h', 0)
            if purchase_rate > 0.1:
                score += 20
            elif purchase_rate > 0.05:
                score += 10
            
            return min(score, 100)
        
        else:
            # Original v1 algorithm
            score = 0
            count_1h = features.get('activity_count_1h', 0)
            
            if count_1h > 5:
                score += 30
            elif count_1h > 2:
                score += 15
            
            if features.get('is_active_session', False):
                score += 20
            
            event_freq = features.get('event_type_frequency_24h', 0)
            if event_freq > 10:
                score += 50
            
            return min(score, 100)
    
    def compute_features(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Compute all ML features from raw event with versioning and A/B testing
        """
        with FEATURE_COMPUTATION_TIME.time():
            user_id = event.get('user_id', 'unknown')
            event_type = event.get('event_type', 'unknown')
            timestamp = event.get('ingested_at', datetime.utcnow().isoformat())
            
            # Determine A/B variant for user
            variant = self.registry.get_user_variant(user_id)
            AB_VARIANT_COUNTER.labels(variant=variant).inc()
            
            features = {
                'user_id': user_id,
                'event_type': event_type,
                'timestamp': timestamp,
                'computed_at': datetime.utcnow().isoformat(),
                'feature_version': self.registry.version,
                'ab_variant': variant,
            }
            
            # Compute temporal features
            temporal_features = self.compute_temporal_features(event, variant)
            features.update(temporal_features)
            
            # Compute categorical features
            categorical_features = self.compute_categorical_features(event, variant)
            features.update(categorical_features)
            
            # Compute windowed aggregations
            window_features = self.compute_windowed_aggregations(user_id, event_type, variant)
            features.update(window_features)
            
            # Time since last event
            last_event_key = f"last_event:{user_id}"
            last_event_time = self.redis_client.get(last_event_key)
            
            if last_event_time:
                try:
                    last_time = datetime.fromisoformat(last_event_time)
                    current_time = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                    features['seconds_since_last_event'] = (current_time - last_time).total_seconds()
                except:
                    features['seconds_since_last_event'] = None
            else:
                features['seconds_since_last_event'] = None
            
            # Update last event time
            self.redis_client.setex(last_event_key, 86400, timestamp)
            
            # Session indicator
            if self.registry.should_compute_feature('is_active_session', variant):
                features['is_active_session'] = features.get('seconds_since_last_event', 1800) < 1800
            
            # New user indicator
            if self.registry.should_compute_feature('is_new_user', variant):
                first_event_key = f"first_event:{user_id}"
                first_event = self.redis_client.get(first_event_key)
                if not first_event:
                    self.redis_client.setex(first_event_key, 86400 * 7, timestamp)
                    features['is_new_user'] = True
                else:
                    try:
                        first_time = datetime.fromisoformat(first_event)
                        current_time = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                        hours_since_first = (current_time - first_time).total_seconds() / 3600
                        features['is_new_user'] = hours_since_first < 24
                    except:
                        features['is_new_user'] = False
            
            # Compute ratio features
            ratio_features = self.compute_ratio_features(user_id, features, variant)
            features.update(ratio_features)
            
            # Compute engagement score (variant-aware)
            engagement_score = self.compute_engagement_score(features, variant)
            if variant == 'B':
                features['engagement_score_v2'] = engagement_score
            else:
                features['engagement_score'] = engagement_score
            
            # Record metrics for drift detection
            self.drift_detector.record_feature_value('engagement_score', engagement_score)
            if 'activity_count_1h' in features:
                self.drift_detector.record_feature_value('activity_count_1h', features['activity_count_1h'])
            
            # Record feature distributions
            FEATURE_VALUE_DISTRIBUTION.labels('engagement_score').observe(engagement_score)
            
            # Add original event data
            features['raw_event'] = event
            
            return features
    
    def _get_activity_count_from_db(self, user_id: str, hours: int = 1) -> int:
        """Get activity count from database for cache miss"""
        try:
            cursor = self.db_conn.cursor()
            cursor.execute("""
                SELECT COUNT(*) 
                FROM raw_events 
                WHERE user_id = %s 
                AND timestamp > NOW() - INTERVAL '%s hours'
            """, (user_id, hours))
            count = cursor.fetchone()[0]
            cursor.close()
            return count
        except Exception as e:
            logger.error(f"Database query failed: {e}")
            return 0
    
    def store_features(self, features: Dict[str, Any]):
        """Store computed features in database with versioning"""
        try:
            cursor = self.db_conn.cursor()
            
            # Build dynamic insert based on computed features
            feature_inserts = []
            for key, value in features.items():
                if key in ['user_id', 'event_type', 'timestamp', 'computed_at', 
                          'feature_version', 'ab_variant', 'raw_event']:
                    continue
                
                # Skip None values
                if value is None:
                    continue
                
                feature_inserts.append((
                    features['user_id'],
                    key,
                    value,
                    features['computed_at'],
                    features.get('feature_version', 'v1'),
                    features.get('ab_variant', 'A')
                ))
            
            if feature_inserts:
                execute_values(cursor, """
                    INSERT INTO features (
                        user_id, feature_name, feature_value, computed_at, feature_version, ab_variant
                    ) VALUES %s
                    ON CONFLICT (user_id, feature_name) 
                    DO UPDATE SET 
                        feature_value = EXCLUDED.feature_value,
                        computed_at = EXCLUDED.computed_at,
                        feature_version = EXCLUDED.feature_version,
                        ab_variant = EXCLUDED.ab_variant
                """, feature_inserts)
                
            self.db_conn.commit()
            cursor.close()
        except Exception as e:
            logger.error(f"Failed to store features: {e}")
            self.db_conn.rollback()
            raise
    
    def process_batch(self, events: List[Dict[str, Any]]):
        """Process multiple events in batch for efficiency"""
        try:
            BATCH_SIZE.observe(len(events))
            
            feature_batch = []
            for event in events:
                try:
                    features = self.compute_features(event)
                    feature_batch.append(features)
                except Exception as e:
                    logger.error(f"Failed to compute features for event: {e}")
                    EVENTS_FAILED.inc()
            
            # Batch store to database
            for features in feature_batch:
                try:
                    self.store_features(features)
                    
                    # Publish to feature-events topic
                    self.producer.send('feature-events', value=features)
                    
                    EVENTS_PROCESSED.inc()
                except Exception as e:
                    logger.error(f"Failed to store/publish features: {e}")
                    EVENTS_FAILED.inc()
                    
            logger.info(f"Processed batch of {len(events)} events")
            
        except Exception as e:
            logger.error(f"Batch processing failed: {e}")
    
    def process_event(self, event: Dict[str, Any]):
        """Process a single event"""
        try:
            # Compute features
            features = self.compute_features(event)
            
            # Store in database
            self.store_features(features)
            
            # Publish to feature-events topic
            self.producer.send('feature-events', value=features)
            
            EVENTS_PROCESSED.inc()
            logger.debug(f"Processed event for user {features['user_id']}")
            
        except Exception as e:
            EVENTS_FAILED.inc()
            logger.error(f"Failed to process event: {e}")
            # Send to dead-letter queue
            try:
                self.producer.send('dead-letter-queue', value={
                    'original_event': event,
                    'error': str(e),
                    'timestamp': datetime.utcnow().isoformat()
                })
            except:
                logger.error("Failed to send to DLQ")
    
    def run(self):
        """Main processing loop with batch support"""
        logger.info("Starting enhanced feature processor...")
        logger.info(f"Feature version: {self.registry.version}")
        logger.info(f"Batch size: {self.batch_size}, Batch timeout: {self.batch_timeout}s")
        
        # Start Prometheus metrics server
        start_http_server(8082)
        logger.info("Metrics server started on :8082")
        
        # Connect to all services
        self.connect()
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.shutdown)
        signal.signal(signal.SIGTERM, self.shutdown)
        
        logger.info("Consuming events from Kafka...")
        
        try:
            for message in self.consumer:
                if not self.running:
                    break
                
                try:
                    event = message.value
                    self.batch.append(event)
                    
                    # Process batch if size reached or timeout
                    time_since_batch = (datetime.utcnow() - self.last_batch_time).total_seconds()
                    
                    if len(self.batch) >= self.batch_size or time_since_batch >= self.batch_timeout:
                        if self.batch:
                            self.process_batch(self.batch)
                            self.batch = []
                            self.last_batch_time = datetime.utcnow()
                    
                except Exception as e:
                    logger.error(f"Error processing message: {e}")
                    EVENTS_FAILED.inc()
                    
            # Process remaining batch
            if self.batch:
                self.process_batch(self.batch)
                    
        except Exception as e:
            logger.error(f"Consumer error: {e}")
        finally:
            self.cleanup()
    
    def shutdown(self, signum, frame):
        """Graceful shutdown"""
        logger.info("Shutting down gracefully...")
        self.running = False
    
    def cleanup(self):
        """Close all connections"""
        if self.consumer:
            self.consumer.close()
        if self.producer:
            self.producer.close()
        if self.db_conn:
            self.db_conn.close()
        if self.redis_client:
            self.redis_client.close()
        logger.info("Cleanup complete")


if __name__ == '__main__':
    processor = EnhancedFeatureProcessor()
    processor.run()
