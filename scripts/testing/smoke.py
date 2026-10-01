#!/usr/bin/env python3
"""
==============================================================================
Enterprise Microservices Smoke Testing Super-Script (smoke.py)
Combines functional frontend-to-backend checks, a dual-target deployment gate,
and an optional bounded, read-only GraphQL resilience probe.
==============================================================================
Usage:
  python scripts/testing/smoke.py
  python scripts/testing/smoke.py --base-url http://localhost:5173 --max-latency-ms 300
  python scripts/testing/smoke.py --resilience
  python scripts/testing/smoke.py --resilience --vus 2 --duration-seconds 30
  python scripts/testing/smoke.py --deployment --base-url http://localhost:8080 --frontend-url http://localhost:5173
  python scripts/testing/smoke.py --json
  python scripts/testing/smoke.py --strict
"""

import os
import sys
import time
import uuid
import json
import argparse
import concurrent.futures
import http.client
import math
import statistics
import urllib.request
import urllib.error
import urllib.parse

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

DEFAULT_FRONTEND = "http://127.0.0.1:5173"
DEFAULT_KEYCLOAK = "http://127.0.0.1:8181"
DEFAULT_ROUTER = "http://127.0.0.1:8080"


DEPLOYMENT_PROBES = [
    {
        "name": "Cosmo Router Supergraph GraphQL Probe",
        "path": "/graphql",
        "target": "router",
        "method": "POST",
        "body": b'{"query": "{ __typename }"}',
        "headers": {"Content-Type": "application/json"},
        "expected_status": [200],
    },
    {
        "name": "Storefront Nginx Health",
        "path": "/healthz",
        "target": "frontend",
        "method": "GET",
        "expected_status": [200],
    },
    {
        "name": "Storefront Frontend Root",
        "path": "/",
        "target": "frontend",
        "method": "GET",
        "expected_status": [200],
    },
]


def _normalize_local_url(url):
    return url.rstrip("/").replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")


def _deployment_request(url, probe, timeout):
    request = urllib.request.Request(
        url,
        data=probe.get("body"),
        method=probe["method"],
        headers={"User-Agent": "DevSecOps-SmokeTest-Agent/3.0", **probe.get("headers", {})},
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
            error = None
            if probe["target"] == "router" and response.status == 200:
                try:
                    result = json.loads(body.decode("utf-8"))
                    if (not isinstance(result, dict) or result.get("errors") or
                            not isinstance(result.get("data"), dict) or
                            not result["data"].get("__typename")):
                        error = "GraphQL response has errors or lacks data.__typename"
                except (UnicodeDecodeError, json.JSONDecodeError) as parse_error:
                    error = f"Invalid GraphQL JSON response: {parse_error}"
            return response.status, (time.perf_counter() - started) * 1000, error
    except urllib.error.HTTPError as error:
        return error.code, (time.perf_counter() - started) * 1000, None
    except Exception as error:
        return 0, (time.perf_counter() - started) * 1000, str(error)


def run_deployment_smoke(router_url, frontend_url, timeout=5.0, max_latency_ms=500.0,
                         retries=3, retry_delay_seconds=3.0, json_output=False):
    """Check Router and storefront independently without placing orders or emitting events."""
    router_url = _normalize_local_url(router_url)
    frontend_url = _normalize_local_url(frontend_url)
    results = []

    if not json_output:
        print("\n=================================================================")
        print(" DEPLOYMENT SMOKE GATE: ROUTER + STOREFRONT")
        print(f" Router   : {router_url}")
        print(f" Frontend : {frontend_url}")
        print(f" Latency SLO: < {max_latency_ms} ms | Timeout: {timeout}s | Retries: {retries}")
        print("-----------------------------------------------------------------")

    for probe in DEPLOYMENT_PROBES:
        base_url = router_url if probe["target"] == "router" else frontend_url
        target_url = f"{base_url}{probe['path']}"
        result = {"status_code": 0, "latency_ms": 0.0, "error": None}
        passed = False
        for attempt in range(retries):
            status, latency_ms, error = _deployment_request(target_url, probe, timeout)
            result = {"status_code": status, "latency_ms": latency_ms, "error": error}
            passed = status in probe["expected_status"] and latency_ms <= max_latency_ms and error is None
            if passed or attempt + 1 >= retries:
                break
            time.sleep(retry_delay_seconds)

        record = {
            "name": probe["name"], "url": target_url, "method": probe["method"],
            "expected_status": probe["expected_status"], "actual_status": result["status_code"],
            "latency_ms": round(result["latency_ms"], 2), "passed": passed, "error": result["error"],
        }
        results.append(record)
        if not json_output:
            status_label = f"HTTP {result['status_code']}" if result["status_code"] else "CONNECTION FAILED"
            print(f" [{'PASS' if passed else 'FAIL'}] {probe['name']:<39} {status_label:<18} ({result['latency_ms']:.1f}ms)")
            if result["error"]:
                print(f"        Error: {result['error']}")

    all_passed = all(item["passed"] for item in results)
    if json_output:
        print(json.dumps({"suite": "deployment", "overall_passed": all_passed, "results": results}, indent=2))
    else:
        print("-----------------------------------------------------------------")
        print("ALL DEPLOYMENT SMOKE GATES PASSED" if all_passed else "DEPLOYMENT SMOKE GATE FAILED")
        print("=================================================================")
    return all_passed

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
    return secret

def acquire_jwt(keycloak_url):
    secret = get_keycloak_secret()
    if not secret:
        return ""
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
    except Exception:
        return ""

class SmokeTester:
    def __init__(self, base_url, keycloak_url, max_latency_ms=500, output_json=False, strict=False):
        self.base_url = base_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")
        self.keycloak_url = keycloak_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")
        self.max_latency_ms = max_latency_ms
        self.output_json = output_json
        self.strict = strict
        self.results = []

    def log_step(self, name, passed, latency_ms=0, details=""):
        self.results.append({
            "check": name,
            "passed": passed,
            "latency_ms": round(latency_ms, 2),
            "details": str(details)
        })
        if not self.output_json:
            badge = "\033[92m[PASS]\033[0m" if passed else "\033[91m[FAIL]\033[0m"
            lat_str = f"({latency_ms:.1f}ms)" if latency_ms > 0 else ""
            print(f"  {badge} {name:<40} {lat_str:<12} {details}")

    def run(self):
        if not self.output_json:
            print("\n\033[96m================================================================================\033[0m")
            print(" \033[96m🔍 ENTERPRISE END-TO-END SMOKE TEST PROBER (smoke.py)\033[0m")
            print(f" Target Frontend: {self.base_url} | Max Latency SLO: {self.max_latency_ms}ms")
            print("\033[96m================================================================================\033[0m")

        # 1. Frontend/Nginx health endpoint
        t0 = time.time()
        try:
            req = urllib.request.Request(f"{self.base_url}/healthz")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                lat = (time.time() - t0) * 1000
                status = data.get("status", "UNKNOWN")
                self.log_step("Frontend Nginx Health (/healthz)", status == "OK", lat, f"Status: {status}")
        except Exception as e:
            self.log_step("Frontend Nginx Health (/healthz)", False, (time.time() - t0) * 1000, f"Error: {e}")

        # 2. Keycloak JWT Authentication
        t0 = time.time()
        token = acquire_jwt(self.keycloak_url)
        lat = (time.time() - t0) * 1000
        self.log_step("Keycloak OIDC JWT Token Acquisition", bool(token), lat, f"Token: {token[:12]}... (Acquired)" if token else "Auth Failed")

        # 3. Cosmo Router GraphQL through frontend Nginx
        t0 = time.time()
        try:
            payload = json.dumps({"query": "{ __typename }"}).encode("utf-8")
            req = urllib.request.Request(
                f"{self.base_url}/graphql",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                result = json.loads(resp.read().decode("utf-8"))
                lat = (time.time() - t0) * 1000
                ok = resp.status == 200 and not result.get("errors") and bool(result.get("data", {}).get("__typename"))
                self.log_step("Cosmo Router GraphQL (/graphql)", ok, lat, "GraphQL response received")
        except Exception as e:
            self.log_step("Cosmo Router GraphQL (/graphql)", False, (time.time() - t0) * 1000, f"Error: {e}")

        # 4. Catalog REST endpoint proxied by Nginx to products-service
        t0 = time.time()
        try:
            req = urllib.request.Request(f"{self.base_url}/api/product")
            with urllib.request.urlopen(req, timeout=5) as resp:
                raw = resp.read().decode("utf-8")
                lat = (time.time() - t0) * 1000
                products = json.loads(raw) if raw.startswith("[") else []
                slo_met = lat <= self.max_latency_ms
                self.log_step("Product Catalog API (/api/product)", len(products) > 0 and slo_met, lat, f"{len(products)} products returned (SLO < {self.max_latency_ms}ms)")
        except Exception as e:
            self.log_step("Product Catalog API (/api/product)", False, (time.time() - t0) * 1000, f"Error: {e}")

        # 5. Authenticated REST order placement proxied by Nginx to orders-service
        if token:
            t0 = time.time()
            order_payload = json.dumps({
                "orderItems": [
                    {
                        "sku": "000001",
                        "price": 69.99,
                        "quantity": 1
                    }
                ],
                "customerName": "Smoke Test Runner",
                "customerEmail": "smoke.runner@example.com",
                "shippingAddress": "100 Enterprise Way",
                "city": "Austin",
                "postalCode": "78701",
                "phone": "+15550001122",
                "deliveryMethod": "STANDARD",
                "shippingFee": 15.0,
                "taxAmount": 10.0,
                "totalAmount": 94.99,
                "paymentMethod": "CARD_VISA"
            }).encode("utf-8")
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}",
                "X-Idempotency-Key": str(uuid.uuid4())
            }
            try:
                req = urllib.request.Request(f"{self.base_url}/api/order", data=order_payload, headers=headers, method="POST")
                with urllib.request.urlopen(req, timeout=5) as resp:
                    lat = (time.time() - t0) * 1000
                    self.log_step("Order Placement with Idempotency Key", resp.status in (200, 201), lat, f"HTTP {resp.status} Created")
            except Exception as e:
                self.log_step("Order Placement with Idempotency Key", False, (time.time() - t0) * 1000, f"Error: {e}")

        # 6. Negative Security Gate (assert 401/403 on unauthenticated order route)
        t0 = time.time()
        unauth_payload = json.dumps({
            "orderItems": [{"sku": "000001", "price": 10.0, "quantity": 1}],
            "customerName": "Smoke Test",
            "customerEmail": "smoke.runner@example.com",
        }).encode("utf-8")
        try:
            req = urllib.request.Request(f"{self.base_url}/api/order", data=unauth_payload, headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=4) as resp:
                lat = (time.time() - t0) * 1000
                self.log_step("Negative Auth Boundary (/api/order)", False, lat, f"FAILED: Unexpected HTTP {resp.status}")
        except urllib.error.HTTPError as e:
            lat = (time.time() - t0) * 1000
            passed = e.code in (401, 403)
            self.log_step("Negative Auth Boundary (/api/order)", passed, lat, f"HTTP {e.code} correctly blocked unauthenticated request")
        except Exception as e:
            self.log_step("Negative Auth Boundary (/api/order)", False, 0, f"Connection error: {e}")

        # 7. Summary Report
        passed_count = sum(1 for r in self.results if r["passed"])
        total_count = len(self.results)
        all_passed = (passed_count == total_count)

        if self.output_json:
            print(json.dumps({
                "summary": {"total": total_count, "passed": passed_count, "failed": total_count - passed_count, "all_passed": all_passed},
                "checks": self.results
            }, indent=2))
        else:
            print("\033[96m--------------------------------------------------------------------------------\033[0m")
            status_color = "\033[92m" if all_passed else "\033[91m"
            print(f" {status_color}RESULTS: {passed_count}/{total_count} checks passed.\033[0m")
            print("\033[96m================================================================================\033[0m")

        if self.strict and not all_passed:
            sys.exit(1)


def run_resilience_probe(base_url, vus=2, duration_seconds=30, interval_seconds=1.0,
                         timeout_seconds=5, p95_threshold_ms=2000,
                         max_error_rate_pct=2.0, output_json=False):
    """Run a bounded, read-only GraphQL load probe with one reusable connection per VU."""
    base_url = base_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("--base-url must be an absolute HTTP or HTTPS URL")

    graphql_path = f"{parsed.path.rstrip('/')}/graphql"
    if parsed.query:
        graphql_path += f"?{parsed.query}"
    connection_type = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    run_started = time.monotonic()
    deadline = time.monotonic() + duration_seconds
    payload = json.dumps({"query": "{ __typename }"})

    def virtual_user(vu_id):
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        connection = connection_type(parsed.hostname, port, timeout=timeout_seconds)
        observations = []
        while time.monotonic() < deadline:
            started = time.perf_counter()
            status = 0
            passed = False
            detail = ""
            try:
                connection.request(
                    "POST", graphql_path, body=payload,
                    headers={"Content-Type": "application/json", "Accept": "application/json"},
                )
                response = connection.getresponse()
                status = response.status
                body = response.read()
                if status == 200:
                    result = json.loads(body.decode("utf-8"))
                    passed = (
                        isinstance(result, dict)
                        and not result.get("errors")
                        and isinstance(result.get("data"), dict)
                        and bool(result["data"].get("__typename"))
                    )
                    if not passed:
                        detail = "GraphQL response contained errors or no __typename data"
                else:
                    detail = f"HTTP {status}"
                if response.will_close:
                    connection.close()
                    connection = connection_type(parsed.hostname, port, timeout=timeout_seconds)
            except Exception as exc:
                detail = f"{type(exc).__name__}: {exc}"
                connection.close()
                connection = connection_type(parsed.hostname, port, timeout=timeout_seconds)

            observations.append({
                "vu": vu_id,
                "status": status,
                "passed": passed,
                "latency_ms": (time.perf_counter() - started) * 1000,
                "detail": detail[:180],
            })
            remaining = deadline - time.monotonic()
            if remaining > 0 and interval_seconds > 0:
                time.sleep(min(interval_seconds, remaining))

        connection.close()
        return observations

    with concurrent.futures.ThreadPoolExecutor(max_workers=vus) as executor:
        futures = [executor.submit(virtual_user, vu_id) for vu_id in range(1, vus + 1)]
        observations = [observation for future in futures for observation in future.result()]
    elapsed = max(time.monotonic() - run_started, 0.001)

    latencies = sorted(item["latency_ms"] for item in observations)
    request_count = len(observations)
    failed_count = sum(1 for item in observations if not item["passed"])
    error_rate_pct = (failed_count / request_count * 100) if request_count else 100.0
    p95_ms = latencies[max(0, math.ceil(0.95 * len(latencies)) - 1)] if latencies else 0.0
    thresholds = {
        "p95_latency_ms": {"actual": round(p95_ms, 2), "limit_exclusive": p95_threshold_ms,
                           "passed": bool(latencies) and p95_ms < p95_threshold_ms},
        "error_rate_pct": {"actual": round(error_rate_pct, 3), "limit_exclusive": max_error_rate_pct,
                            "passed": bool(request_count) and error_rate_pct < max_error_rate_pct},
    }
    all_passed = all(check["passed"] for check in thresholds.values())
    status_counts = {}
    for item in observations:
        key = str(item["status"])
        status_counts[key] = status_counts.get(key, 0) + 1
    failures = [item for item in observations if not item["passed"]]
    report = {
        "suite": "resilience",
        "target": f"{parsed.scheme}://{parsed.netloc}{graphql_path}",
        "summary": {
            "passed": all_passed,
            "requests": request_count,
            "failed_requests": failed_count,
            "requests_per_second": round(request_count / elapsed, 2),
            "mean_latency_ms": round(statistics.fmean(latencies), 2) if latencies else 0,
            "p95_latency_ms": round(p95_ms, 2),
            "max_latency_ms": round(max(latencies), 2) if latencies else 0,
            "http_status_counts": status_counts,
        },
        "thresholds": thresholds,
        "failure_samples": failures[:5],
    }

    if output_json:
        print(json.dumps(report, indent=2))
    else:
        print("\n================================================================================")
        print(" BOUNDED GRAPHQL RESILIENCE SMOKE TEST")
        print(f" Target: {report['target']}")
        print(f" Load: {vus} virtual users for {duration_seconds}s; {interval_seconds}s interval")
        print("--------------------------------------------------------------------------------")
        print(f" Requests: {request_count} | Failed: {failed_count} | Rate: {report['summary']['requests_per_second']} req/s")
        print(f" Latency: mean {report['summary']['mean_latency_ms']}ms | p95 {report['summary']['p95_latency_ms']}ms | max {report['summary']['max_latency_ms']}ms")
        for name, check in thresholds.items():
            label = "PASS" if check["passed"] else "FAIL"
            unit = "ms" if name == "p95_latency_ms" else "%"
            print(f" [{label}] {name}: {check['actual']}{unit} (limit < {check['limit_exclusive']}{unit})")
        if failures:
            print(" Failure samples:")
            for failure in failures[:5]:
                print(f"  - VU {failure['vu']} HTTP {failure['status']}: {failure['detail']}")
        print("================================================================================")

    return all_passed


def main():
    parser = argparse.ArgumentParser(description="Functional, deployment, and bounded resilience smoke checks")
    parser.add_argument("--base-url", help="Frontend base URL (functional/resilience modes); Router/Gateway URL with --deployment")
    parser.add_argument("--frontend-url", default=os.getenv("FRONTEND_URL", DEFAULT_FRONTEND), help="Frontend/Nginx URL used by --deployment")
    parser.add_argument("--keycloak-url", default=os.getenv("KEYCLOAK_URL", DEFAULT_KEYCLOAK), help="Keycloak IAM URL")
    parser.add_argument("--max-latency-ms", type=int, default=500, help="Maximum allowed latency SLO threshold in ms")
    parser.add_argument("--deployment", action="store_true", help="Check Router GraphQL and Frontend health/root independently; read-only, no order placement")
    parser.add_argument("--timeout", type=float, default=5.0, help="Per-request HTTP timeout for --deployment (default: 5s)")
    parser.add_argument("--retries", type=int, default=3, help="Attempts per endpoint for --deployment (default: 3)")
    parser.add_argument("--retry-delay-seconds", type=float, default=3.0, help="Delay between --deployment retries (default: 3s)")
    parser.add_argument("--resilience", action="store_true", help="Run only the bounded, read-only GraphQL load suite (does not place orders)")
    parser.add_argument("--vus", type=int, default=2, help="Virtual users for --resilience (1-20; default: 2)")
    parser.add_argument("--duration-seconds", type=int, default=30, help="Duration for --resilience (1-600; default: 30)")
    parser.add_argument("--request-interval-seconds", type=float, default=1.0, help="Pause per VU between requests (0.1-60; default: 1)")
    parser.add_argument("--request-timeout-seconds", type=int, default=5, help="Per-request timeout for --resilience (1-60; default: 5)")
    parser.add_argument("--p95-threshold-ms", type=float, default=2000, help="Exclusive p95 latency threshold for --resilience (default: 2000)")
    parser.add_argument("--max-error-rate-pct", type=float, default=2.0, help="Exclusive failed-request percentage for --resilience (default: 2)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--strict", action="store_true", help="Exit with non-zero status code if any check fails")

    args = parser.parse_args()
    frontend_base_url = args.base_url or os.getenv("FRONTEND_URL", DEFAULT_FRONTEND)
    if args.deployment and args.resilience:
        parser.error("--deployment and --resilience are separate suites; choose one")
    if args.deployment:
        if args.timeout <= 0 or args.max_latency_ms <= 0 or args.retries < 1 or args.retry_delay_seconds < 0:
            parser.error("--timeout and --max-latency-ms must be positive, --retries at least 1, and --retry-delay-seconds non-negative")
        passed = run_deployment_smoke(
            router_url=args.base_url or os.getenv("TARGET_URL") or os.getenv("BASE_URL") or DEFAULT_ROUTER,
            frontend_url=args.frontend_url,
            timeout=args.timeout,
            max_latency_ms=args.max_latency_ms,
            retries=args.retries,
            retry_delay_seconds=args.retry_delay_seconds,
            json_output=args.json,
        )
        sys.exit(0 if passed else 1)
    if args.resilience:
        if not 1 <= args.vus <= 20:
            parser.error("--vus must be between 1 and 20 for the local rate-limited frontend")
        if not 1 <= args.duration_seconds <= 600:
            parser.error("--duration-seconds must be between 1 and 600")
        if not 0.1 <= args.request_interval_seconds <= 60:
            parser.error("--request-interval-seconds must be between 0.1 and 60")
        if not 1 <= args.request_timeout_seconds <= 60:
            parser.error("--request-timeout-seconds must be between 1 and 60")
        if args.p95_threshold_ms <= 0:
            parser.error("--p95-threshold-ms must be greater than zero")
        if not 0 < args.max_error_rate_pct <= 100:
            parser.error("--max-error-rate-pct must be greater than 0 and at most 100")
        passed = run_resilience_probe(
            frontend_base_url,
            vus=args.vus,
            duration_seconds=args.duration_seconds,
            interval_seconds=args.request_interval_seconds,
            timeout_seconds=args.request_timeout_seconds,
            p95_threshold_ms=args.p95_threshold_ms,
            max_error_rate_pct=args.max_error_rate_pct,
            output_json=args.json,
        )
        if not passed:
            sys.exit(1)
        return

    SmokeTester(frontend_base_url, args.keycloak_url, max_latency_ms=args.max_latency_ms, output_json=args.json, strict=args.strict).run()

if __name__ == "__main__":
    main()
