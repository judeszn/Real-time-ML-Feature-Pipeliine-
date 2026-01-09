#!/usr/bin/env python3
"""
Shopping Store Event Simulator
Generates realistic e-commerce events for the ML feature pipeline
"""

import requests
import random
import time
import json
import logging
from datetime import datetime
from typing import Dict, List
import argparse
import threading

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Shopping store products
PRODUCTS = {
    "laptop": {"category": "electronics", "price": 1200.0},
    "phone": {"category": "electronics", "price": 800.0},
    "headphones": {"category": "electronics", "price": 150.0},
    "keyboard": {"category": "electronics", "price": 100.0},
    "monitor": {"category": "electronics", "price": 350.0},
    "shirt": {"category": "clothing", "price": 40.0},
    "jeans": {"category": "clothing", "price": 60.0},
    "shoes": {"category": "clothing", "price": 90.0},
    "jacket": {"category": "clothing", "price": 120.0},
    "book": {"category": "books", "price": 25.0},
    "notebook": {"category": "books", "price": 10.0},
}

EVENTS_TYPES = ["login", "view", "add_to_cart", "remove_from_cart", "purchase", "logout"]


class ShoppingUser:
    """Simulates a single user's shopping behavior"""
    
    def __init__(self, user_id: str, ingestion_url: str):
        self.user_id = user_id
        self.ingestion_url = ingestion_url
        self.in_session = False
        self.cart = []
        self.event_count = 0
        
    def send_event(self, event_type: str, product: str = None, quantity: int = 1) -> bool:
        """Send event to ingestion service"""
        try:
            event = {
                "user_id": self.user_id,
                "event_type": event_type,
                "timestamp": datetime.utcnow().isoformat(),
            }
            
            if product:
                event["product"] = product
                event["product_category"] = PRODUCTS[product]["category"]
                event["product_price"] = PRODUCTS[product]["price"]
                event["quantity"] = quantity
            
            response = requests.post(
                self.ingestion_url,
                json=event,
                timeout=5
            )
            
            if response.status_code == 200:
                self.event_count += 1
                logger.info(f"✓ {self.user_id} | {event_type:15} | Total: {self.event_count}")
                return True
            else:
                logger.warning(f"✗ {self.user_id} | {event_type} | Status: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"✗ {self.user_id} | {event_type} | Error: {e}")
            return False
    
    def simulate_session(self):
        """Simulate a shopping session"""
        # Login
        self.send_event("login")
        self.in_session = True
        time.sleep(random.uniform(1, 3))
        
        # Browse products (3-8 products)
        num_views = random.randint(3, 8)
        for _ in range(num_views):
            product = random.choice(list(PRODUCTS.keys()))
            self.send_event("view", product=product)
            time.sleep(random.uniform(2, 5))
        
        # Add to cart (1-4 items)
        num_cart = random.randint(1, 4)
        for _ in range(num_cart):
            product = random.choice(list(PRODUCTS.keys()))
            qty = random.randint(1, 3)
            self.send_event("add_to_cart", product=product, quantity=qty)
            self.cart.append(product)
            time.sleep(random.uniform(1, 3))
        
        # Maybe remove an item (30% chance)
        if self.cart and random.random() < 0.3:
            product = random.choice(self.cart)
            self.send_event("remove_from_cart", product=product)
            self.cart.remove(product)
            time.sleep(random.uniform(1, 2))
        
        # Purchase (70% conversion rate)
        if self.cart and random.random() < 0.7:
            for product in self.cart:
                self.send_event("purchase", product=product)
                time.sleep(random.uniform(0.5, 1))
        
        # Logout
        self.send_event("logout")
        self.in_session = False
        self.cart = []


class EventSimulator:
    """Main event simulator coordinator"""
    
    def __init__(self, ingestion_url: str, num_users: int = 5, events_per_minute: int = 10):
        self.ingestion_url = ingestion_url
        self.num_users = num_users
        self.events_per_minute = events_per_minute
        self.total_events = 0
        self.users = [ShoppingUser(f"user_{i}", ingestion_url) for i in range(num_users)]
        
    def run_continuous(self, duration_seconds: int = None):
        """Run continuous event generation"""
        logger.info(f"🛍️  Starting Shopping Store Simulator")
        logger.info(f"   Users: {self.num_users}")
        logger.info(f"   Target: {self.events_per_minute} events/min")
        logger.info(f"   Endpoint: {self.ingestion_url}")
        logger.info(f"{'=' * 70}")
        
        start_time = time.time()
        
        try:
            while True:
                # Check duration if specified
                if duration_seconds and (time.time() - start_time) > duration_seconds:
                    logger.info("✓ Duration limit reached, stopping simulator")
                    break
                
                # Randomly pick a user to start a session
                user = random.choice(self.users)
                
                # Run session in background thread
                thread = threading.Thread(target=user.simulate_session, daemon=True)
                thread.start()
                
                # Calculate sleep time based on events_per_minute
                # Average session generates ~12 events
                session_interval = (60 / self.events_per_minute) * 12
                time.sleep(session_interval)
                
        except KeyboardInterrupt:
            logger.info("\n⏹️  Simulator stopped by user")
            self._print_stats()
    
    def run_load_test(self, concurrent_users: int = 10, duration_seconds: int = 60):
        """Run a load test with concurrent users"""
        logger.info(f"📊 Starting Load Test")
        logger.info(f"   Concurrent users: {concurrent_users}")
        logger.info(f"   Duration: {duration_seconds}s")
        logger.info(f"{'=' * 70}")
        
        threads = []
        start_time = time.time()
        
        try:
            # Launch concurrent user sessions
            for i in range(concurrent_users):
                user = ShoppingUser(f"load_test_user_{i}", self.ingestion_url)
                thread = threading.Thread(target=user.simulate_session, daemon=True)
                thread.start()
                threads.append(thread)
                time.sleep(0.1)  # Stagger starts
            
            # Wait for duration
            while (time.time() - start_time) < duration_seconds:
                active = sum(1 for t in threads if t.is_alive())
                logger.info(f"Active threads: {active}/{concurrent_users}")
                time.sleep(5)
            
            # Wait for remaining threads
            for thread in threads:
                thread.join(timeout=30)
            
            logger.info("✓ Load test completed")
            
        except KeyboardInterrupt:
            logger.info("\n⏹️  Load test stopped by user")
    
    def _print_stats(self):
        """Print simulator statistics"""
        total = sum(user.event_count for user in self.users)
        logger.info(f"\n{'=' * 70}")
        logger.info(f"📈 Simulator Statistics:")
        for user in self.users:
            logger.info(f"   {user.user_id}: {user.event_count} events")
        logger.info(f"   TOTAL: {total} events")
        logger.info(f"{'=' * 70}")


def main():
    parser = argparse.ArgumentParser(description="Shopping Store Event Simulator")
    parser.add_argument(
        "--url",
        default="http://localhost:8085/events",
        help="Ingestion service URL (default: http://localhost:8085/events)"
    )
    parser.add_argument(
        "--users",
        type=int,
        default=5,
        help="Number of simulated users (default: 5)"
    )
    parser.add_argument(
        "--events-per-minute",
        type=int,
        default=10,
        help="Target events per minute (default: 10)"
    )
    parser.add_argument(
        "--load-test",
        type=int,
        metavar="CONCURRENT_USERS",
        help="Run load test with N concurrent users (overrides normal mode)"
    )
    parser.add_argument(
        "--duration",
        type=int,
        metavar="SECONDS",
        help="Run for N seconds then stop (default: run forever)"
    )
    
    args = parser.parse_args()
    
    # Verify endpoint is reachable
    try:
        response = requests.get(args.url.replace("/events", "/health"), timeout=5)
        if response.status_code != 200:
            logger.warning(f"⚠️  Warning: Endpoint returned {response.status_code}")
    except Exception as e:
        logger.error(f"✗ Cannot reach {args.url}: {e}")
        logger.error("  Make sure the ingestion service is running!")
        return
    
    simulator = EventSimulator(
        ingestion_url=args.url,
        num_users=args.users,
        events_per_minute=args.events_per_minute
    )
    
    if args.load_test:
        simulator.run_load_test(
            concurrent_users=args.load_test,
            duration_seconds=args.duration or 60
        )
    else:
        simulator.run_continuous(duration_seconds=args.duration)


if __name__ == "__main__":
    main()
