#!/usr/bin/env python3
"""
Distributed DDoS & Rate-Limit Attack Simulator for Spring Boot Microservices Architecture.
Simulates a multi-IP botnet flooding Spring Cloud Gateway to test Grafana security dashboards,
Prometheus rate-limiting metrics (HTTP 429), and live Loki audit log streaming.

Usage:
  python scripts/testing/simulate-ddos.py
  python scripts/testing/simulate-ddos.py --burst
  python scripts/testing/simulate-ddos.py --distributed
  python scripts/testing/simulate-ddos.py --no-auth

Configurable via Environment Variables:
  GATEWAY_URL=http://localhost:8080 KEYCLOAK_URL=http://localhost:8181 REQUESTS=300 CONCURRENCY=15 MODE=burst python scripts/testing/simulate-ddos.py
"""

import os
import sys
import time
import urllib.request
import urllib.error
import json
import threading
import statistics
from concurrent.futures import ThreadPoolExecutor

# Ensure UTF-8 output on Windows terminals
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

# Target configuration
GATEWAY_URL = os.environ.get('GATEWAY_URL', os.environ.get('BASE_URL', f"http://{os.environ.get('TARGET_HOST', 'localhost')}:{os.environ.get('TARGET_PORT', '8080')}"))
KEYCLOAK_URL = os.environ.get('KEYCLOAK_URL', 'http://localhost:8181')
BASE_URL = GATEWAY_URL

# Attack parameters
TOTAL_REQUESTS = int(os.environ.get('REQUESTS', '300'))
CONCURRENCY = int(os.environ.get('CONCURRENCY', '15'))
DISABLE_AUTH = '--no-auth' in sys.argv or os.environ.get('NO_AUTH', '').lower() in ('1', 'true', 'yes')

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

    def record(self, status_code, latency_ms):
        with self.lock:
            self.total += 1
            self.latencies.append(latency_ms)
            self.status_codes[status_code] = self.status_codes.get(status_code, 0) + 1

            if status_code in (200, 201):
                self.ok += 1
                sys.stdout.write('\033[32m.\033[0m')  # Green dot for 200/201 OK
            elif status_code == 429:
                self.blocked += 1
                sys.stdout.write('\033[33m!\033[0m')  # Yellow ! for 429 Rate Limit
            elif status_code == 401:
                self.unauth += 1
                sys.stdout.write('\033[34mU\033[0m')  # Blue U for 401 Unauthorized
            elif status_code == 0:
                self.failed += 1
                sys.stdout.write('\033[35m?\033[0m')  # Magenta ? for network drop
            else:
                self.error += 1
                sys.stdout.write('\033[31mX\033[0m')  # Red X for 4xx/5xx errors
            sys.stdout.flush()


# Attack mode: 'burst' (single IP flood to trigger 429 rate limit denials) or 'distributed' (rotates 12 botnet IPs)
if '--distributed' in sys.argv:
    ATTACK_MODE = 'distributed'
elif '--burst' in sys.argv:
    ATTACK_MODE = 'burst'
else:
    ATTACK_MODE = os.environ.get('MODE', 'burst')

BURST_IP = '198.51.100.42'
stats = AttackStats()
JWT_TOKEN = ""


def acquire_jwt_token():
    global JWT_TOKEN
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
            JWT_TOKEN = body.get("access_token", "")
            print(f"\033[92m[✓] Keycloak JWT Token Acquired ({len(JWT_TOKEN)} chars)\033[0m")
    except Exception as e:
        print(f"\033[93m[!] Keycloak direct grant note ({e}), proceeding with anonymous traffic\033[0m")


def send_attack_request(req_id):
    if ATTACK_MODE == 'burst':
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
    if JWT_TOKEN and not DISABLE_AUTH:
        headers['Authorization'] = f"Bearer {JWT_TOKEN}"

    req = urllib.request.Request(url, headers=headers, method='GET')
    start_time = time.perf_counter()

    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            latency_ms = (time.perf_counter() - start_time) * 1000
            stats.record(resp.getcode(), latency_ms)
    except urllib.error.HTTPError as e:
        latency_ms = (time.perf_counter() - start_time) * 1000
        stats.record(e.code, latency_ms)
    except Exception:
        latency_ms = (time.perf_counter() - start_time) * 1000
        stats.record(0, latency_ms)


def run_simulation():
    print('\n======================================================================')
    print('  🛡️  SPRING CLOUD - DISTRIBUTED ATTACK & RATE-LIMIT SIMULATOR        ')
    print('======================================================================')
    print(f"  Target Gateway:  {BASE_URL}")
    print(f"  Attack Mode:     {ATTACK_MODE.upper()} ({'Single-IP aggressive flood (Triggers 429)' if ATTACK_MODE == 'burst' else '12-IP distributed botnet'})")
    print(f"  Total Requests:  {TOTAL_REQUESTS} requests ({CONCURRENCY} concurrent threads)")
    print(f"  Assault Paths:   {', '.join(TARGET_PATHS)}")
    
    if not DISABLE_AUTH:
        acquire_jwt_token()
    else:
        print("  Auth Mode:       ANONYMOUS (Forced --no-auth)")
    print('======================================================================\n')
    print('  Launching attack flood now...\n')

    start_time = time.perf_counter()

    with ThreadPoolExecutor(max_workers=CONCURRENCY) as executor:
        list(executor.map(send_attack_request, range(TOTAL_REQUESTS)))

    duration = time.perf_counter() - start_time
    avg_latency = statistics.mean(stats.latencies) if stats.latencies else 0
    p95_latency = statistics.quantiles(stats.latencies, n=20)[18] if len(stats.latencies) >= 20 else avg_latency
    p99_latency = statistics.quantiles(stats.latencies, n=100)[98] if len(stats.latencies) >= 100 else p95_latency
    rps = stats.total / duration if duration > 0 else 0

    print('\n\n======================================================================')
    print('  📊 ATTACK SIMULATION RESULTS & TELEMETRY SUMMARY                    ')
    print('======================================================================')
    print(f"  Total Duration:         {duration:.2f}s")
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
    print('  🔭 Live Grafana Dashboards:')
    print('   * ☸️  Kubernetes Master:      http://localhost:3000/d/kubernetes-master/dd5cbaa')
    print('   * 🐳 Docker Compose Master:  http://localhost:3000/d/docker-compose-master/e83a309')
    print('   * 🔍 Grafana Explore (Logs): http://localhost:3000/explore\n')


if __name__ == '__main__':
    run_simulation()
