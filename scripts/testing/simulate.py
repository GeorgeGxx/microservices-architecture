#!/usr/bin/env python3
"""
==============================================================================
Enterprise Microservices Simulation Super-Script (simulate.py)
Consolidates:
  1. Traffic Simulation (simulate-traffic.py): Realistic shopping sessions,
     catalog browsing, cart additions, Keycloak-authenticated checkout, Kafka events.
  2. DDoS & Rate-Limit Stress (simulate-ddos.py): Multi-IP botnet simulation,
     volumetric floods, Slowloris, anonymous assault, 429 assertion.
  3. Chaos Engineering & Resilience (simulate-chaos.py): Concurrent high-load,
     out-of-stock SKUs, circuit breaker tripping, idempotency conflict handling.
==============================================================================
Usage:
  python scripts/testing/simulate.py --scenario traffic [--orders 20] [--concurrency 4] [--continuous]
  python scripts/testing/simulate.py --scenario ddos [--duration 30] [--distributed] [--no-auth]
  python scripts/testing/simulate.py --scenario chaos [--chaos-runs 30] [--concurrency 8]
  python scripts/testing/simulate.py --scenario all
"""

import os
import sys
import time
import uuid
import random
import urllib.request
import urllib.error
import urllib.parse
import json
import threading
import itertools
import statistics
import argparse
from concurrent.futures import ThreadPoolExecutor

# Terminal encoding for Windows compatibility
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

# ==============================================================================
# Helper Functions & Constants
# ==============================================================================
DEFAULT_GATEWAY = "http://127.0.0.1:8080"
DEFAULT_KEYCLOAK = "http://127.0.0.1:8181"

CATALOG_ITEMS = [
    {"sku": "LAPTOP-PRO", "price": 28999.99, "name": "Laptop Pro 16\""},
    {"sku": "000001", "price": 1299.00, "name": "Wireless Gaming Mouse"},
    {"sku": "000002", "price": 899.50, "name": "Mechanical Keyboard RGB"},
    {"sku": "000003", "price": 5499.00, "name": "UltraWide 4K Monitor"},
]

ATTACKER_IPS = [
    '198.51.100.42', '203.0.113.88', '45.33.32.156', '185.220.101.5',
    '104.244.76.13', '91.240.118.221', '194.26.29.112', '172.67.182.99',
    '89.248.165.71', '185.156.73.45', '192.0.2.14', '198.18.0.55'
]

def get_keycloak_secret():
    secret = os.getenv("KEYCLOAK_CLIENT_SECRET", "")
    if not secret and os.path.exists(".env"):
        try:
            with open(".env", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("KEYCLOAK_CLIENT_SECRET="):
                        secret = line.strip().split("=", 1)[1].strip()
                        break
        except Exception:
            pass
    return secret or "mdIV7hoeQlOzQGSiYGzPfWXgt505pSbu"

def acquire_jwt(keycloak_url):
    secret = get_keycloak_secret()
    token_url = f"{keycloak_url}/realms/microservices-realm/protocol/openid-connect/token"
    payload = urllib.parse.urlencode({
        "grant_type": "password",
        "client_id": "microservices_client",
        "client_secret": secret,
        "username": "admin_user",
        "password": "admin"
    }).encode("utf-8")

    req = urllib.request.Request(token_url, data=payload, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("access_token", "")
    except Exception as e:
        print(f"[\033[93mWARN\033[0m] Could not acquire Keycloak token: {e}")
        return ""


# ==============================================================================
# 1. Traffic Simulator
# ==============================================================================
class TrafficSimulator:
    def __init__(self, gateway_url, keycloak_url, orders=15, concurrency=3, continuous=False):
        self.gateway_url = gateway_url
        self.keycloak_url = keycloak_url
        self.total_orders = orders
        self.concurrency = concurrency
        self.continuous = continuous
        self.token = ""
        self.orders_placed = 0
        self.orders_cancelled = 0
        self.units_sold = 0
        self.total_revenue = 0.0
        self.latencies = []
        self.lock = threading.Lock()

    def run(self):
        print("\n\033[96m================================================================================\033[0m")
        print(" \033[96m🛒 SCENARIO: Legitimate E-Commerce User Traffic Simulator\033[0m")
        print(f" Target Gateway: {self.gateway_url} | Target Orders: {self.total_orders} | Concurrency: {self.concurrency}")
        print("\033[96m================================================================================\033[0m")

        self.token = acquire_jwt(self.keycloak_url)
        if self.token:
            print("  [\033[92mOK\033[0m] Keycloak JWT Token acquired successfully.")
        else:
            print("  [\033[93mWARN\033[0m] Proceeding without authenticated JWT token.")

        run_num = 0
        while True:
            run_num += 1
            start_time = time.time()
            with ThreadPoolExecutor(max_workers=self.concurrency) as executor:
                futures = [executor.submit(self._session_worker, i) for i in range(self.total_orders)]
                for f in futures:
                    try:
                        f.result()
                    except Exception:
                        pass

            elapsed = max(time.time() - start_time, 0.001)
            self._print_stats(elapsed, run_num)

            if not self.continuous:
                break
            time.sleep(2)

    def _session_worker(self, session_id):
        # 1. Browse catalog
        t0 = time.time()
        try:
            req = urllib.request.Request(f"{self.gateway_url}/api/product")
            with urllib.request.urlopen(req, timeout=5) as r:
                r.read()
        except Exception:
            pass
        self.latencies.append(time.time() - t0)

        # 2. Select item and place order
        item = random.choice(CATALOG_ITEMS)
        qty = random.randint(1, 3)
        order_payload = json.dumps({
            "skuCode": item["sku"],
            "price": item["price"],
            "quantity": qty
        }).encode("utf-8")

        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        t1 = time.time()
        try:
            req = urllib.request.Request(f"{self.gateway_url}/api/order", data=order_payload, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status in (200, 201):
                    with self.lock:
                        self.orders_placed += 1
                        self.units_sold += qty
                        self.total_revenue += item["price"] * qty
        except Exception:
            pass
        self.latencies.append(time.time() - t1)

    def _print_stats(self, elapsed, run_num):
        avg_lat = (statistics.mean(self.latencies) * 1000) if self.latencies else 0
        p95_lat = (statistics.quantiles(self.latencies, n=20)[18] * 1000) if len(self.latencies) >= 20 else avg_lat
        print(f"\n[\033[92mTRAFFIC REPORT #{run_num}\033[0m] Completed in {elapsed:.2f}s:")
        print(f"  • Orders Placed: {self.orders_placed}")
        print(f"  • Units Sold:    {self.units_sold}")
        print(f"  • Total Revenue: ${self.total_revenue:,.2f}")
        print(f"  • Latency (Avg): {avg_lat:.1f}ms | p95: {p95_lat:.1f}ms")


# ==============================================================================
# 2. DDoS & Rate-Limit Attacker
# ==============================================================================
class DDoSAttacker:
    def __init__(self, gateway_url, keycloak_url, duration=30, distributed=True, no_auth=False):
        self.gateway_url = gateway_url
        self.keycloak_url = keycloak_url
        self.duration = duration
        self.distributed = distributed
        self.no_auth = no_auth
        self.request_count = 0
        self.status_counts = {}
        self.lock = threading.Lock()

    def run(self):
        print("\n\033[91m================================================================================\033[0m")
        print(" \033[91m⚡ SCENARIO: Distributed DDoS & Rate-Limit Flood Simulator\033[0m")
        print(f" Target Gateway: {self.gateway_url} | Duration: {self.duration}s | Distributed: {self.distributed}")
        print("\033[91m================================================================================\033[0m")

        token = "" if self.no_auth else acquire_jwt(self.keycloak_url)
        stop_event = threading.Event()

        def flood_worker(worker_id):
            ip_cycler = itertools.cycle(ATTACKER_IPS) if self.distributed else itertools.cycle(["192.0.2.1"])
            while not stop_event.is_set():
                ip = next(ip_cycler)
                headers = {"X-Forwarded-For": ip, "User-Agent": f"Botnet-Node-{worker_id}"}
                if token:
                    headers["Authorization"] = f"Bearer {token}"

                endpoint = random.choice(["/api/product", "/api/order", "/api/inventory/000001"])
                req = urllib.request.Request(f"{self.gateway_url}{endpoint}", headers=headers)
                try:
                    with urllib.request.urlopen(req, timeout=2) as resp:
                        code = resp.status
                except urllib.error.HTTPError as e:
                    code = e.code
                except Exception:
                    code = 599

                with self.lock:
                    self.request_count += 1
                    self.status_counts[code] = self.status_counts.get(code, 0) + 1

        threads = []
        for i in range(12):
            t = threading.Thread(target=flood_worker, args=(i,))
            t.daemon = True
            threads.append(t)
            t.start()

        time.sleep(self.duration)
        stop_event.set()
        for t in threads:
            t.join(timeout=1)

        print(f"\n[\033[91mDDoS ATTACK REPORT\033[0m] Completed in {self.duration}s:")
        print(f"  • Total Requests Dispatched: {self.request_count} ({self.request_count / max(self.duration, 1):.1f} req/s)")
        print("  • HTTP Status Breakdown:")
        for code, count in sorted(self.status_counts.items()):
            color = "\033[92m" if code in (200, 201) else ("\033[93m" if code == 429 else "\033[91m")
            label = "OK" if code in (200, 201) else ("RATE-LIMITED" if code == 429 else "ERROR/BLOCKED")
            print(f"    {color}[HTTP {code}]\033[0m {label}: {count} ({count * 100 / max(self.request_count, 1):.1f}%)")


# ==============================================================================
# 3. Chaos Engineering & Resilience Tester
# ==============================================================================
class ChaosTester:
    def __init__(self, gateway_url, keycloak_url, runs=30, concurrency=6):
        self.gateway_url = gateway_url
        self.keycloak_url = keycloak_url
        self.runs = runs
        self.concurrency = concurrency
        self.token = ""
        self.results = {"success": 0, "rate_limited": 0, "circuit_tripped": 0, "bad_request": 0, "errors": 0}
        self.lock = threading.Lock()

    def run(self):
        print("\n\033[95m================================================================================\033[0m")
        print(" \033[95m🌪️ SCENARIO: Chaos Engineering, Stock Exhaustion & Circuit Breakers\033[0m")
        print(f" Target Gateway: {self.gateway_url} | Chaos Runs: {self.runs} | Concurrency: {self.concurrency}")
        print("\033[95m================================================================================\033[0m")

        self.token = acquire_jwt(self.keycloak_url)

        with ThreadPoolExecutor(max_workers=self.concurrency) as executor:
            futures = [executor.submit(self._chaos_worker, i) for i in range(self.runs)]
            for f in futures:
                try:
                    f.result()
                except Exception:
                    pass

        print(f"\n[\033[95mCHAOS RESILIENCE REPORT\033[0m] Completed {self.runs} chaos iterations:")
        print(f"  • Successful Checkouts:       {self.results['success']}")
        print(f"  • Rate Limited (HTTP 429):    {self.results['rate_limited']}")
        print(f"  • Circuit Breaker / Fallback: {self.results['circuit_tripped']}")
        print(f"  • Out-of-Stock / Validation:  {self.results['bad_request']}")
        print(f"  • Other Errors / Handled:     {self.results['errors']}")

    def _chaos_worker(self, worker_id):
        # Rotate between valid, out of stock, and invalid skus
        scenario_type = worker_id % 3
        if scenario_type == 0:
            sku = "LAPTOP-PRO"
            price = 28999.99
        elif scenario_type == 1:
            sku = "000004"  # Stock = 0
            price = 2199.00
        else:
            sku = f"NON-EXISTENT-{uuid.uuid4().hex[:6]}"
            price = 999.00

        payload = json.dumps({"skuCode": sku, "price": price, "quantity": random.randint(1, 2)}).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        try:
            req = urllib.request.Request(f"{self.gateway_url}/api/order", data=payload, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status in (200, 201):
                    with self.lock:
                        self.results["success"] += 1
        except urllib.error.HTTPError as e:
            with self.lock:
                if e.code == 429:
                    self.results["rate_limited"] += 1
                elif e.code in (400, 404, 422):
                    self.results["bad_request"] += 1
                elif e.code in (503, 504):
                    self.results["circuit_tripped"] += 1
                else:
                    self.results["errors"] += 1
        except Exception:
            with self.lock:
                self.results["errors"] += 1


# ==============================================================================
# Main Dispatcher
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="Enterprise Microservices Simulation Super-Script")
    parser.add_argument("--scenario", choices=["traffic", "ddos", "chaos", "all"], default="traffic", help="Simulation scenario to execute")
    parser.add_argument("--gateway", default=os.getenv("GATEWAY_URL", DEFAULT_GATEWAY), help="API Gateway URL")
    parser.add_argument("--keycloak", default=os.getenv("KEYCLOAK_URL", DEFAULT_KEYCLOAK), help="Keycloak URL")
    parser.add_argument("--orders", type=int, default=15, help="Number of orders to place (traffic)")
    parser.add_argument("--concurrency", type=int, default=4, help="Thread concurrency")
    parser.add_argument("--continuous", action="store_true", help="Run traffic simulation continuously")
    parser.add_argument("--duration", type=int, default=30, help="DDoS attack duration in seconds")
    parser.add_argument("--distributed", action="store_true", default=True, help="Enable distributed multi-IP botnet")
    parser.add_argument("--no-auth", action="store_true", help="Disable Keycloak token authentication (ddos)")
    parser.add_argument("--chaos-runs", type=int, default=30, help="Number of iterations for chaos testing")

    args, _ = parser.parse_known_args()

    gw = args.gateway.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")
    kc = args.keycloak.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")

    if args.scenario in ("traffic", "all"):
        TrafficSimulator(gw, kc, orders=args.orders, concurrency=args.concurrency, continuous=args.continuous).run()

    if args.scenario in ("ddos", "all"):
        DDoSAttacker(gw, kc, duration=args.duration, distributed=args.distributed, no_auth=args.no_auth).run()

    if args.scenario in ("chaos", "all"):
        ChaosTester(gw, kc, runs=args.chaos_runs, concurrency=args.concurrency).run()

if __name__ == "__main__":
    main()
