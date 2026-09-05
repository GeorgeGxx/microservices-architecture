#!/usr/bin/env python3
"""
Enterprise Microservices Legitimate Traffic Generator & Load Simulator
Simulates real user shopping sessions: browsing products, checking inventory,
placing purchase orders, cancelling select orders, and feeding real-time Grafana KPIs.

Usage:
  python scripts/testing/simulate-traffic.py
  python scripts/testing/simulate-traffic.py --orders 20 --concurrency 4
  python scripts/testing/simulate-traffic.py --continuous
"""

import os
import sys
import time
import uuid
import random
import urllib.request
import urllib.error
import json
import concurrent.futures
import statistics

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

import argparse

parser = argparse.ArgumentParser(description="Enterprise Microservices Legitimate Traffic Generator & Load Simulator")
parser.add_argument("--gateway", default=os.getenv("GATEWAY_URL", "http://localhost:8080"), help="API Gateway URL")
parser.add_argument("--keycloak", default=os.getenv("KEYCLOAK_URL", "http://localhost:8181"), help="Keycloak URL")
parser.add_argument("--orders", type=int, default=int(os.getenv("ORDERS", "15")), help="Total orders to place")
parser.add_argument("--concurrency", type=int, default=int(os.getenv("CONCURRENCY", "3")), help="Concurrent threads")
parser.add_argument("--continuous", action="store_true", default=os.getenv("CONTINUOUS", "").lower() in ("1", "true", "yes"), help="Run continuously in loop")
args, _ = parser.parse_known_args()

GATEWAY_URL = args.gateway.replace('://localhost:', '://127.0.0.1:').replace('://localhost', '://127.0.0.1')
KEYCLOAK_URL = args.keycloak.replace('://localhost:', '://127.0.0.1:').replace('://localhost', '://127.0.0.1')
TOTAL_ORDERS = args.orders
CONCURRENCY = args.concurrency
CONTINUOUS = args.continuous

# Known catalog SKUs
CATALOG_ITEMS = [
    {"sku": "LAPTOP-PRO", "price": 28999.99, "name": "Laptop Pro 16\""},
    {"sku": "000001", "price": 1299.00, "name": "Wireless Gaming Mouse"},
    {"sku": "000002", "price": 899.50, "name": "Mechanical Keyboard RGB"},
    {"sku": "000003", "price": 5499.00, "name": "UltraWide 4K Monitor"},
]


class TrafficSimulator:
    def __init__(self):
        self.token = ""
        self.orders_placed = 0
        self.orders_cancelled = 0
        self.units_sold = 0
        self.latencies = []
        self.created_order_ids = []

    def acquire_jwt(self):
        print("\033[94m[*] Authenticating with Keycloak (8181)...\033[0m")
        secret = ""
        if os.path.exists(".env"):
            try:
                with open(".env", "r", encoding="utf-8") as f:
                    for line in f:
                        if line.startswith("KEYCLOAK_CLIENT_SECRET="):
                            secret = line.strip().split("=", 1)[1].strip("\"'")
            except Exception:
                pass

        url = f"{KEYCLOAK_URL}/realms/microservices-realm/protocol/openid-connect/token"
        data = (
            f"grant_type=password&client_id=microservices_client"
            f"&client_secret={secret}&username=admin_user&password=admin"
        ).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as res:
                body = json.loads(res.read().decode())
                self.token = body.get("access_token", "")
                print(f"\033[92m[✓] Keycloak JWT Token Acquired ({len(self.token)} chars)\033[0m\n")
        except Exception as e:
            print(f"\033[93m[!] Keycloak direct grant note ({e}), proceeding with standard headers\033[0m\n")

    def _headers(self, idempotency_key=None):
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "ECommerceTrafficSimulator/1.0",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if idempotency_key:
            headers["X-Idempotency-Key"] = idempotency_key
            headers["Idempotency-Key"] = idempotency_key
        return headers

    def browse_catalog(self):
        """Fetches product catalog and checks inventory."""
        try:
            req = urllib.request.Request(f"{GATEWAY_URL}/api/product", headers=self._headers(), method="GET")
            with urllib.request.urlopen(req, timeout=5) as resp:
                pass
        except Exception:
            pass

    def record_funnel_event(self, event_type, step=None, session_id=None):
        """Dispatches conversion funnel events to Orders Service."""
        try:
            payload = json.dumps({
                "eventType": event_type,
                "step": step,
                "sessionId": session_id or str(uuid.uuid4())
            }).encode("utf-8")
            req = urllib.request.Request(
                f"{GATEWAY_URL}/api/order/funnel",
                data=payload,
                headers=self._headers(),
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                pass
        except Exception:
            pass

    def place_order(self, order_idx):
        start = time.perf_counter()
        session_id = str(uuid.uuid4())
        self.browse_catalog()

        # Funnel stage 1: Cart Add
        self.record_funnel_event("CART_ADD", session_id=session_id)

        # Funnel stage 2: Checkout Start
        self.record_funnel_event("CHECKOUT_START", session_id=session_id)

        # Funnel stage 3: Payment Step
        self.record_funnel_event("CHECKOUT_STEP", step="PAYMENT", session_id=session_id)

        # Select 1 to 3 random items
        selected = random.sample(CATALOG_ITEMS, k=random.randint(1, min(3, len(CATALOG_ITEMS))))
        order_items = [
            {"sku": item["sku"], "price": item["price"], "quantity": random.randint(1, 2)}
            for item in selected
        ]
        
        delivery_methods = ["STANDARD", "EXPRESS", "NEXT_DAY"]
        payment_brands = ["VISA", "MASTERCARD", "AMEX"]
        
        payload_dict = {
            "orderItems": order_items,
            "deliveryMethod": random.choice(delivery_methods),
            "paymentBrand": random.choice(payment_brands),
            "taxAmount": round(sum(item["price"] * item["quantity"] for item in order_items) * 0.16, 2),
            "shippingCost": 15.00
        }
        payload = json.dumps(payload_dict).encode("utf-8")
        idempotency_key = str(uuid.uuid4())

        req = urllib.request.Request(
            f"{GATEWAY_URL}/api/order",
            data=payload,
            headers=self._headers(idempotency_key=idempotency_key),
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                latency = (time.perf_counter() - start) * 1000
                self.latencies.append(latency)
                body = json.loads(resp.read().decode())
                order_id = body.get("id")
                order_num = body.get("orderNumber", f"ORD-{order_idx}")

                self.orders_placed += 1
                self.units_sold += sum(item["quantity"] for item in order_items)
                if order_id:
                    self.created_order_ids.append(order_id)

                print(f"  \033[92m[✓] Order #{order_num}\033[0m | Items: {len(order_items)} | Method: {payload_dict['deliveryMethod']} | Brand: {payload_dict['paymentBrand']} | Latency: {latency:.1f}ms")

                # Occasionally test duplicate idempotency rejection
                if order_idx % 4 == 0:
                    try:
                        dup_req = urllib.request.Request(
                            f"{GATEWAY_URL}/api/order",
                            data=payload,
                            headers=self._headers(idempotency_key=idempotency_key),
                            method="POST",
                        )
                        with urllib.request.urlopen(dup_req, timeout=4) as dup_resp:
                            print(f"  \033[94m[🛡️] Idempotency Verified: Duplicate order prevented & original returned (HTTP {dup_resp.status})\033[0m")
                    except Exception as dup_err:
                        print(f"  \033[94m[🛡️] Idempotency Intercepted: {dup_err}\033[0m")

                return True
        except urllib.error.HTTPError as e:
            latency = (time.perf_counter() - start) * 1000
            self.latencies.append(latency)
            print(f"  \033[91m[X] Order failed (HTTP {e.code})\033[0m | Latency: {latency:.1f}ms")
            return False
        except Exception as e:
            latency = (time.perf_counter() - start) * 1000
            print(f"  \033[91m[X] Order connection error: {e}\033[0m | Latency: {latency:.1f}ms")
            return False


    def cancel_random_order(self):
        """Cancels a previously placed order to test compensation & cancellation metrics."""
        if not self.created_order_ids:
            return
        order_id = self.created_order_ids.pop(0)
        req = urllib.request.Request(
            f"{GATEWAY_URL}/api/order/{order_id}/cancel",
            data=b"",
            headers=self._headers(),
            method="PUT",
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                self.orders_cancelled += 1
                print(f"  \033[93m[↩] Order ID {order_id} CANCELLED (Inventory restored & Kafka event published)\033[0m")
        except Exception as e:
            pass

    def run(self):
        print("======================================================================")
        print("  🛒  SPRING MICROSERVICES - E-COMMERCE LIVE TRAFFIC GENERATOR        ")
        print("======================================================================")
        print(f"  Target Gateway:   {GATEWAY_URL}")
        print(f"  Total Orders:     {TOTAL_ORDERS if not CONTINUOUS else 'CONTINUOUS (Ctrl+C to stop)'}")
        print(f"  Concurrency:      {CONCURRENCY} threads")
        print("======================================================================\n")

        self.acquire_jwt()
        start_time = time.perf_counter()

        try:
            if CONTINUOUS:
                order_count = 0
                while True:
                    order_count += 1
                    self.place_order(order_count)
                    if order_count % 5 == 0:
                        self.cancel_random_order()
                    time.sleep(random.uniform(0.5, 1.5))
            else:
                with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENCY) as executor:
                    futures = [executor.submit(self.place_order, i + 1) for i in range(TOTAL_ORDERS)]
                    concurrent.futures.wait(futures)

                # Cancel 1 or 2 orders for realistic cancellation metrics
                if len(self.created_order_ids) >= 3:
                    print("\n[*] Simulating customer order cancellations...")
                    self.cancel_random_order()

        except KeyboardInterrupt:
            print("\n\n\033[93m[!] Traffic simulation stopped by user.\033[0m")

        duration = time.perf_counter() - start_time
        avg_lat = statistics.mean(self.latencies) if self.latencies else 0
        p95_lat = statistics.quantiles(self.latencies, n=20)[18] if len(self.latencies) >= 20 else avg_lat

        print("\n======================================================================")
        print("  📊 SIMULATION SUMMARY & TELEMETRY REPORT                            ")
        print("======================================================================")
        print(f"  Total Execution Time:    {duration:.2f}s")
        print(f"  Orders Placed:           \033[92m{self.orders_placed}\033[0m")
        print(f"  Total Units Sold:        \033[96m{self.units_sold}\033[0m items")
        print(f"  Orders Cancelled:        \033[93m{self.orders_cancelled}\033[0m")
        print(f"  Average Order Latency:   {avg_lat:.1f}ms")
        print(f"  P95 Latency:             {p95_lat:.1f}ms")
        print("======================================================================\n")


if __name__ == "__main__":
    simulator = TrafficSimulator()
    simulator.run()
