#!/usr/bin/env python3
"""
Distributed DDoS & Rate-Limit Attack Simulator for Spring Boot Microservices Architecture.
Simulates a multi-IP botnet flooding Spring Cloud Gateway to test Grafana security dashboards,
Prometheus rate-limiting metrics (HTTP 429), and live Loki audit log streaming.

Usage:
  python scripts/testing/simulate-ddos.py                     # 30s sustained attack (default)
  python scripts/testing/simulate-ddos.py --duration 60       # 60s sustained attack
  python scripts/testing/simulate-ddos.py --continuous        # Run indefinitely until Ctrl+C
  python scripts/testing/simulate-ddos.py --requests 300      # Fast 300-request burst
  python scripts/testing/simulate-ddos.py --distributed       # 12-IP botnet simulation
  python scripts/testing/simulate-ddos.py --no-auth           # Anonymous traffic without Keycloak token
"""

import os
import sys
import time
import urllib.request
import urllib.error
import json
import threading
import itertools
import statistics
import argparse
from concurrent.futures import ThreadPoolExecutor

# Ensure UTF-8 output on Windows terminals
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

# Target configuration
DEFAULT_HOST = '127.0.0.1'
RAW_GATEWAY = os.environ.get('GATEWAY_URL', os.environ.get('BASE_URL', f"http://{os.environ.get('TARGET_HOST', DEFAULT_HOST)}:{os.environ.get('TARGET_PORT', '8080')}"))
RAW_KEYCLOAK = os.environ.get('KEYCLOAK_URL', f"http://{DEFAULT_HOST}:8181")

GATEWAY_URL = RAW_GATEWAY.replace('://localhost:', '://127.0.0.1:').replace('://localhost', '://127.0.0.1')
KEYCLOAK_URL = RAW_KEYCLOAK.replace('://localhost:', '://127.0.0.1:').replace('://localhost', '://127.0.0.1')
BASE_URL = GATEWAY_URL

# Botnet IP pool to simulate distributed attack sources
ATTACKER_IPS = [
    '198.51.100.42',
    '203.0.113.88',
    '45.33.32.156',
    '185.220.101.5',
    '104.244.76.13',
    '91.240.118.221',
    '194.26.29.112',
    '172.67.182.99',
    '89.248.165.71',
    '185.156.73.45',
    '192.0.2.14',
    '198.18.0.55',
]

# Real microservice endpoints under assault
TARGET_PATHS = [
    '/api/product',
    '/api/inventory/LAPTOP-PRO',
    '/api/inventory/000001',
    '/api/inventory/000002',
    '/api/order',
    '/actuator/health',
]

# Diverse User-Agents to simulate various flood engines
USER_AGENTS = [
    'Mozilla/5.0 (compatible; MiraiBot/2.1; +http://botnet.example)',
    'sqlmap/1.6#stable',
    'curl/7.88.1 (x86_64-pc-linux-gnu)',
    'Python-urllib/3.11 (FloodEngine/v3)',
    'Java/21 (StressClient/v2)',
    'Apache-HttpClient/4.5.13',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
]

BURST_IP = '198.51.100.42'


class AttackStats:
    def __init__(self):
        self.lock = threading.Lock()
        self.total = 0
        self.ok = 0          # 2xx
        self.blocked = 0     # 429 Rate Limited
        self.unauth = 0      # 401 Unauthorized
        self.error = 0       # 4xx / 5xx
        self.failed = 0      # Network timeouts / drops
        self.latencies = []
        self.status_codes = {}

    def record(self, status_code, latency_ms, print_char=False):
        with self.lock:
            self.total += 1
            if len(self.latencies) < 5000:
                self.latencies.append(latency_ms)
            self.status_codes[status_code] = self.status_codes.get(status_code, 0) + 1

            if status_code in (200, 201):
                self.ok += 1
                char = '\033[32m.\033[0m'
            elif status_code == 429:
                self.blocked += 1
                char = '\033[33m!\033[0m'
            elif status_code == 401:
                self.unauth += 1
                char = '\033[34mU\033[0m'
            elif status_code == 0:
                self.failed += 1
                char = '\033[35m?\033[0m'
            else:
                self.error += 1
                char = '\033[31mX\033[0m'

            if print_char:
                sys.stdout.write(char)
                sys.stdout.flush()


def acquire_jwt_token():
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
            token = body.get("access_token", "")
            print(f"\033[92m[✓] Keycloak JWT Token Acquired ({len(token)} chars)\033[0m")
            return token
    except Exception as e:
        print(f"\033[93m[!] Keycloak direct grant note ({e}), proceeding with anonymous traffic\033[0m")
        return ""


def send_attack_request(req_id, stats, attack_mode, jwt_token, disable_auth, print_char=False):
    if attack_mode == 'burst':
        ip = BURST_IP
    else:
        ip = ATTACKER_IPS[req_id % len(ATTACKER_IPS)]

    path = TARGET_PATHS[req_id % len(TARGET_PATHS)]
    user_agent = USER_AGENTS[req_id % len(USER_AGENTS)]
    url = f"{BASE_URL}{path}"

    headers = {
        'User-Agent': user_agent,
        'X-Forwarded-For': ip,
        'X-Real-IP': ip,
        'Accept': 'application/json',
    }
    if jwt_token and not disable_auth:
        headers['Authorization'] = f"Bearer {jwt_token}"

    req = urllib.request.Request(url, headers=headers, method='GET')
    start_time = time.perf_counter()

    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            latency_ms = (time.perf_counter() - start_time) * 1000
            stats.record(resp.getcode(), latency_ms, print_char=print_char)
    except urllib.error.HTTPError as e:
        latency_ms = (time.perf_counter() - start_time) * 1000
        stats.record(e.code, latency_ms, print_char=print_char)
    except Exception:
        latency_ms = (time.perf_counter() - start_time) * 1000
        stats.record(0, latency_ms, print_char=print_char)


def run_simulation():
    parser = argparse.ArgumentParser(description="Distributed DDoS & Rate-Limit Attack Simulator")
    parser.add_argument("--duration", "-d", type=float, default=float(os.environ.get("DURATION", "30")),
                        help="Duration in seconds for sustained attack (default: 30s)")
    parser.add_argument("--requests", "-r", type=int, default=int(os.environ.get("REQUESTS", "0")),
                        help="Exact number of requests to send (overrides duration mode if > 0)")
    parser.add_argument("--concurrency", "-c", type=int, default=int(os.environ.get("CONCURRENCY", "15")),
                        help="Number of concurrent worker threads (default: 15)")
    parser.add_argument("--mode", "-m", choices=["burst", "distributed"],
                        default="distributed" if "--distributed" in sys.argv else ("burst" if "--burst" in sys.argv else os.environ.get("MODE", "burst")),
                        help="Attack mode: burst (single IP) or distributed (multi-IP)")
    parser.add_argument("--no-auth", action="store_true", default=os.environ.get("NO_AUTH", "").lower() in ("1", "true", "yes"),
                        help="Force anonymous mode without JWT token")
    parser.add_argument("--continuous", action="store_true", default=os.environ.get("CONTINUOUS", "").lower() in ("1", "true", "yes"),
                        help="Run continuously until interrupted with Ctrl+C")
    parser.add_argument("--burst", action="store_true", help="Shortcut for --mode burst")
    parser.add_argument("--distributed", action="store_true", help="Shortcut for --mode distributed")

    args, _ = parser.parse_known_args()

    attack_mode = "distributed" if args.distributed else ("burst" if args.burst else args.mode)
    disable_auth = args.no_auth
    concurrency = args.concurrency
    stats = AttackStats()

    # Determine execution mode: fixed request count vs sustained duration vs continuous
    is_fixed_requests = args.requests > 0 and "--duration" not in sys.argv and "-d" not in sys.argv
    duration_secs = 0 if is_fixed_requests else (999999 if args.continuous else args.duration)

    print('\n======================================================================')
    print('  🛡️  SPRING CLOUD - DISTRIBUTED ATTACK & RATE-LIMIT SIMULATOR        ')
    print('======================================================================')
    print(f"  Target Gateway:  {BASE_URL}")
    print(f"  Attack Mode:     {attack_mode.upper()} ({'Single-IP flood (Targeted 429)' if attack_mode == 'burst' else '12-IP botnet distribution'})")
    if args.continuous:
        print(f"  Execution:       CONTINUOUS (Runs indefinitely until Ctrl+C, {concurrency} threads)")
    elif is_fixed_requests:
        print(f"  Execution:       BURST ({args.requests} requests, {concurrency} threads)")
    else:
        print(f"  Execution:       SUSTAINED ({duration_secs:.0f}s duration flood, {concurrency} threads)")
    print(f"  Assault Paths:   {', '.join(TARGET_PATHS)}")

    jwt_token = ""
    if not disable_auth:
        jwt_token = acquire_jwt_token()
    else:
        print("  Auth Mode:       ANONYMOUS (Forced --no-auth)")
    print('======================================================================\n')

    start_time = time.perf_counter()

    if is_fixed_requests:
        print('  Launching fixed request flood...\n')
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            list(executor.map(lambda req_id: send_attack_request(req_id, stats, attack_mode, jwt_token, disable_auth, print_char=True), range(args.requests)))
    else:
        desc = "CONTINUOUS FLOOD (Press Ctrl+C to stop)" if args.continuous else f"SUSTAINED FLOOD FOR {duration_secs:.0f}s"
        print(f"  🚀 Launching {desc}...\n")
        stop_event = threading.Event()
        counter = itertools.count()

        def worker():
            while not stop_event.is_set():
                send_attack_request(next(counter), stats, attack_mode, jwt_token, disable_auth, print_char=False)

        workers = []
        for _ in range(concurrency):
            t = threading.Thread(target=worker, daemon=True)
            t.start()
            workers.append(t)

        last_total = 0
        last_time = start_time

        try:
            while True:
                time.sleep(1.0)
                now = time.perf_counter()
                elapsed = now - start_time
                delta_t = now - last_time
                current_rps = (stats.total - last_total) / delta_t if delta_t > 0 else 0
                last_total = stats.total
                last_time = now

                pct_blocked = (stats.blocked / stats.total * 100) if stats.total > 0 else 0
                threat = "\033[91mUNDER ATTACK / DDOS (RED)\033[0m" if stats.blocked > 10 else "\033[92mELEVATED\033[0m"

                time_str = f"{elapsed:.0f}s / {duration_secs:.0f}s" if not args.continuous else f"{elapsed:.0f}s"
                sys.stdout.write(
                    f"\r  \033[93m[⚡ ATTACKING]\033[0m Time: {time_str} | "
                    f"RPS: {current_rps:5.1f} | "
                    f"200 OK: \033[32m{stats.ok:4d}\033[0m | "
                    f"429 Throttled: \033[33m{stats.blocked:4d}\033[0m ({pct_blocked:4.1f}%) | "
                    f"Threat: {threat}  "
                )
                sys.stdout.flush()

                if not args.continuous and elapsed >= duration_secs:
                    break
        except KeyboardInterrupt:
            print("\n\n  [!] Attack stopped by user (Ctrl+C). Cleaning up...")
        finally:
            stop_event.set()
            for t in workers:
                t.join(timeout=1.0)

    duration = time.perf_counter() - start_time
    avg_latency = statistics.mean(stats.latencies) if stats.latencies else 0
    p95_latency = statistics.quantiles(stats.latencies, n=20)[18] if len(stats.latencies) >= 20 else avg_latency
    p99_latency = statistics.quantiles(stats.latencies, n=100)[98] if len(stats.latencies) >= 100 else p95_latency
    rps = stats.total / duration if duration > 0 else 0

    print('\n\n======================================================================')
    print('  📊 ATTACK SIMULATION RESULTS & TELEMETRY SUMMARY                    ')
    print('======================================================================')
    print(f"  Total Duration:         {duration:.2f}s")
    print(f"  Total Requests:         {stats.total}")
    print(f"  Aggregate Throughput:    {rps:.1f} req/sec")
    print(f"  Average Latency:         {avg_latency:.1f} ms")
    print(f"  P95 Latency:             {p95_latency:.1f} ms")
    print(f"  P99 Latency:             {p99_latency:.1f} ms")
    print('----------------------------------------------------------------------')
    print(f"  Passed (200/201 OK):    \033[32m{stats.ok}\033[0m")
    print(f"  Throttled (HTTP 429):   \033[33m{stats.blocked}\033[0m (Redis Token Bucket Denials)")
    if stats.unauth > 0:
        print(f"  Unauthorized (HTTP 401):\033[34m{stats.unauth}\033[0m (Security Protected)")
    print(f"  Client/Server Errors:   \033[31m{stats.error}\033[0m")
    print(f"  Dropped / Timeouts:     {stats.failed}")
    print('======================================================================\n')
    print('  🔭 Live Grafana Telemetry:')
    print('   * 🛡️ Technical & Security:  http://localhost:3000/d/technical-security')
    print('   * 🔍 Incident Logs (Loki):   http://localhost:3000/explore\n')


if __name__ == '__main__':
    run_simulation()

