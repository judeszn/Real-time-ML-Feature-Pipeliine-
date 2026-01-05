from flask import Flask, jsonify, request
import redis
import psycopg2
import os
import logging
from datetime import datetime
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Prometheus metrics
API_REQUESTS = Counter('api_requests_total', 'Total API requests', ['endpoint', 'method', 'status'])
API_LATENCY = Histogram('api_latency_seconds', 'API request latency', ['endpoint'])
CACHE_HITS = Counter('api_cache_hits_total', 'API cache hits')
CACHE_MISSES = Counter('api_cache_misses_total', 'API cache misses')

# Redis client
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'redis'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    db=0,
    decode_responses=True,
    socket_connect_timeout=5,
    max_connections=50
)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('POSTGRES_HOST', 'timescaledb'),
    'port': int(os.getenv('POSTGRES_PORT', '5432')),
    'database': os.getenv('POSTGRES_DB', 'featurestore'),
    'user': os.getenv('POSTGRES_USER', 'postgres'),
    'password': os.getenv('POSTGRES_PASSWORD', 'postgres')
}

def get_db_connection():
    """Get database connection"""
    return psycopg2.connect(**DB_CONFIG)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    try:
        # Check Redis
        redis_client.ping()
        redis_status = "healthy"
    except:
        redis_status = "unhealthy"
    
    try:
        # Check Database
        conn = get_db_connection()
        conn.close()
        db_status = "healthy"
    except:
        db_status = "unhealthy"
    
    status = "healthy" if redis_status == "healthy" and db_status == "healthy" else "degraded"
    
    return jsonify({
        'status': status,
        'redis': redis_status,
        'database': db_status,
        'timestamp': datetime.utcnow().isoformat()
    })

@app.route('/features/<user_id>', methods=['GET'])
def get_features(user_id):
    """
    Get all features for a user
    Tries Redis cache first, falls back to database
    """
    with API_LATENCY.labels(endpoint='/features/<user_id>').time():
        try:
            # Try cache first
            cache_key = f"features:{user_id}"
            cached_features = redis_client.get(cache_key)
            
            if cached_features:
                CACHE_HITS.inc()
                API_REQUESTS.labels(endpoint='/features', method='GET', status='200').inc()
                import json
                return jsonify({
                    'user_id': user_id,
                    'features': json.loads(cached_features),
                    'source': 'cache',
                    'timestamp': datetime.utcnow().isoformat()
                })
            
            # Cache miss - query database
            CACHE_MISSES.inc()
            conn = get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT feature_name, feature_value, computed_at
                FROM features
                WHERE user_id = %s
                ORDER BY computed_at DESC
            """, (user_id,))
            
            rows = cursor.fetchall()
            cursor.close()
            conn.close()
            
            if not rows:
                API_REQUESTS.labels(endpoint='/features', method='GET', status='404').inc()
                return jsonify({'error': 'User not found'}), 404
            
            # Build features dict
            features = {}
            for row in rows:
                feature_name, feature_value, computed_at = row
                features[feature_name] = {
                    'value': feature_value,
                    'computed_at': computed_at.isoformat() if hasattr(computed_at, 'isoformat') else str(computed_at)
                }
            
            # Cache for 5 minutes
            import json
            redis_client.setex(cache_key, 300, json.dumps(features))
            
            API_REQUESTS.labels(endpoint='/features', method='GET', status='200').inc()
            return jsonify({
                'user_id': user_id,
                'features': features,
                'source': 'database',
                'timestamp': datetime.utcnow().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error fetching features: {e}")
            API_REQUESTS.labels(endpoint='/features', method='GET', status='500').inc()
            return jsonify({'error': str(e)}), 500

@app.route('/features/<user_id>/<feature_name>', methods=['GET'])
def get_single_feature(user_id, feature_name):
    """Get a specific feature for a user"""
    with API_LATENCY.labels(endpoint='/features/<user_id>/<feature_name>').time():
        try:
            # Try cache first
            cache_key = f"feature:{user_id}:{feature_name}"
            cached_value = redis_client.get(cache_key)
            
            if cached_value:
                CACHE_HITS.inc()
                API_REQUESTS.labels(endpoint='/features/single', method='GET', status='200').inc()
                return jsonify({
                    'user_id': user_id,
                    'feature_name': feature_name,
                    'value': cached_value,
                    'source': 'cache'
                })
            
            # Cache miss - query database
            CACHE_MISSES.inc()
            conn = get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT feature_value, computed_at
                FROM features
                WHERE user_id = %s AND feature_name = %s
                ORDER BY computed_at DESC
                LIMIT 1
            """, (user_id, feature_name))
            
            row = cursor.fetchone()
            cursor.close()
            conn.close()
            
            if not row:
                API_REQUESTS.labels(endpoint='/features/single', method='GET', status='404').inc()
                return jsonify({'error': 'Feature not found'}), 404
            
            feature_value, computed_at = row
            
            # Cache for 5 minutes
            redis_client.setex(cache_key, 300, str(feature_value))
            
            API_REQUESTS.labels(endpoint='/features/single', method='GET', status='200').inc()
            return jsonify({
                'user_id': user_id,
                'feature_name': feature_name,
                'value': feature_value,
                'computed_at': computed_at.isoformat() if hasattr(computed_at, 'isoformat') else str(computed_at),
                'source': 'database'
            })
            
        except Exception as e:
            logger.error(f"Error fetching feature: {e}")
            API_REQUESTS.labels(endpoint='/features/single', method='GET', status='500').inc()
            return jsonify({'error': str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/', methods=['GET'])
def index():
    """API documentation"""
    return jsonify({
        'service': 'Feature Serving API',
        'version': '1.0.0',
        'endpoints': {
            '/health': 'Health check',
            '/features/<user_id>': 'Get all features for a user',
            '/features/<user_id>/<feature_name>': 'Get specific feature for a user',
            '/metrics': 'Prometheus metrics'
        }
    })

if __name__ == '__main__':
    logger.info("Starting Feature Serving API on :8083")
    app.run(host='0.0.0.0', port=8083, debug=False)
