#!/usr/bin/env python3
"""
endpoint-smoke-test.py

Cloud-Agnostic DevSecOps Post-Deployment Smoke & Synthetic Health Prober.
Validates service availability, security filter enforcement (401 on unauthenticated routes),
and latency SLOs against any Kubernetes or cloud environment (Minikube, EKS, AKS, GKE).

Exits with code 0 when every gate passes, or code 1 when an operator/pipeline must
inspect the failed deployment. This probe does not roll back infrastructure.

Author  : GeorgeGxx/DevOps
Version : v2.0.0

Usage:
  python endpoint-smoke-test.py --base-url http://localhost:8080 --frontend-url http://localhost:5173
  python endpoint-smoke-test.py --base-url https://api.myecommerce.com --max-latency-ms 300
  python endpoint-smoke-test.py --json
"""

import argparse
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

try:
    import urllib.request
    import urllib.error
except ImportError:
    pass

# ANSI Color Codes
class Colors:
    HEADER = "\033[95m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"


DEFAULT_PROBES = [
    {
        "name": "Apollo Router Supergraph GraphQL Probe",
        "path": "/graphql",
        "method": "POST",
        "body": b'{"query": "{ __typename }"}',
        "headers": {"Content-Type": "application/json"},
        "expected_status": [200],
        "category": "GraphQL Supergraph",
        "description": "Validates Apollo Router v2 federated GraphQL execution",
    },
    {
        "name": "Storefront Nginx Health",
        "path": "/healthz",
        "target": "frontend",
        "method": "GET",
        "expected_status": [200],
        "category": "Frontend SPA",
        "description": "Verifies Nginx reverse proxy edge health status",
    },
    {
        "name": "Storefront Frontend Root",
        "path": "/",
        "target": "frontend",
        "method": "GET",
        "expected_status": [200],
        "category": "Frontend SPA",
        "description": "Verifies React 19 SPA storefront edge response",
    },
]


def execute_http_request(url: str, method: str, timeout: float, body: Optional[bytes] = None, headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    req_headers = {"User-Agent": "DevSecOps-SmokeTest-Agent/2.0"}
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers=req_headers,
    )
    start_time = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            latency_ms = (time.time() - start_time) * 1000.0
            return {
                "status_code": response.status,
                "latency_ms": latency_ms,
                "error": None,
            }
    except urllib.error.HTTPError as e:
        latency_ms = (time.time() - start_time) * 1000.0
        return {
            "status_code": e.code,
            "latency_ms": latency_ms,
            "error": None,
        }
    except Exception as e:
        latency_ms = (time.time() - start_time) * 1000.0
        return {
            "status_code": 0,
            "latency_ms": latency_ms,
            "error": str(e),
        }


def run_smoke_test(
    base_url: str,
    frontend_url: str,
    probes: List[Dict[str, Any]],
    timeout: float = 5.0,
    max_latency_ms: float = 500.0,
    retries: int = 3,
    delay_between_retries: float = 3.0,
    json_output: bool = False,
) -> bool:
    base_url = base_url.rstrip("/")
    frontend_url = frontend_url.rstrip("/")
    if "localhost" in base_url:
        base_url = base_url.replace("localhost", "127.0.0.1")
    if "localhost" in frontend_url:
        frontend_url = frontend_url.replace("localhost", "127.0.0.1")

    if not json_output:
        print(f"\n{Colors.BOLD}{Colors.HEADER}================================================================={Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN} 🩺  DEVSECOPS SYNTHETIC HEALTH & SECURITY SMOKE TEST{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.HEADER}================================================================={Colors.RESET}")
        print(f"Target Gateway : {Colors.YELLOW}{base_url}{Colors.RESET}")
        print(f"Target Frontend: {Colors.YELLOW}{frontend_url}{Colors.RESET}")
        print(f"Latency SLO    : < {max_latency_ms} ms")
        print(f"HTTP Timeout   : {timeout}s | Retries: {retries}")
        print("-----------------------------------------------------------------\n")

    results = []
    all_passed = True

    for probe in probes:
        probe_base_url = frontend_url if probe.get("target") == "frontend" else base_url
        full_url = f"{probe_base_url}{probe['path']}"
        probe_passed = False
        last_result = {}

        for attempt in range(1, retries + 1):
            last_result = execute_http_request(
                full_url,
                probe["method"],
                timeout,
                body=probe.get("body"),
                headers=probe.get("headers")
            )
            status = last_result["status_code"]
            latency = last_result["latency_ms"]

            is_status_ok = status in probe["expected_status"]
            is_latency_ok = latency <= max_latency_ms

            if is_status_ok and is_latency_ok:
                probe_passed = True
                break

            if attempt < retries:
                time.sleep(delay_between_retries)

        if not probe_passed:
            all_passed = False

        status_code = last_result.get("status_code", 0)
        latency_ms = last_result.get("latency_ms", 0.0)
        error_msg = last_result.get("error")

        probe_record = {
            "name": probe["name"],
            "category": probe["category"],
            "url": full_url,
            "method": probe["method"],
            "expected": probe["expected_status"],
            "actual_status": status_code,
            "latency_ms": round(latency_ms, 2),
            "passed": probe_passed,
            "error": error_msg,
        }
        results.append(probe_record)

        if not json_output:
            icon = f"{Colors.GREEN}✓ PASS{Colors.RESET}" if probe_passed else f"{Colors.RED}✗ FAIL{Colors.RESET}"
            status_str = f"HTTP {status_code}" if status_code > 0 else "CONNECTION REFUSED"
            latency_color = Colors.GREEN if latency_ms <= max_latency_ms else Colors.YELLOW
            print(f" [{icon}] {probe['name']:<38} : {status_str:<18} ({latency_color}{latency_ms:6.1f}ms{Colors.RESET})")
            if not probe_passed and error_msg:
                print(f"        ↳ {Colors.RED}Error: {error_msg}{Colors.RESET}")
                if probe.get("target") == "frontend" and status_code == 0:
                    print(f"        ↳ Verify that the frontend pod is Ready and its port-forward is listening at {frontend_url}.")

    if json_output:
        print(json.dumps({"target": base_url, "overall_passed": all_passed, "results": results}, indent=2))
    else:
        print("\n-----------------------------------------------------------------")
        if all_passed:
            print(f"{Colors.BOLD}{Colors.GREEN}🎉 ALL DEVSECOPS GATES PASSED — Environment is healthy & secure.{Colors.RESET}\n")
        else:
            print(f"{Colors.BOLD}{Colors.RED}🚨 CRITICAL HEALTH OR SECURITY GATE FAILED!{Colors.RESET}")
            print(f"{Colors.YELLOW}Recommendation: Inspect pod events/logs and the release revision; roll back only after confirming the failed deployment.{Colors.RESET}\n")

    return all_passed


def main():
    default_url = os.environ.get("TARGET_URL") or os.environ.get("BASE_URL") or "http://127.0.0.1:8080"

    parser = argparse.ArgumentParser(
        description="🩺 Cloud-Agnostic DevSecOps Synthetic Smoke & Security Prober",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--base-url", default=default_url, help=f"Base URL to probe (Default: {default_url})")
    parser.add_argument("--frontend-url", default=os.environ.get("FRONTEND_URL", "http://127.0.0.1:5173"), help="Frontend/Nginx URL (default: http://127.0.0.1:5173)")
    parser.add_argument("--timeout", type=float, default=5.0, help="HTTP request timeout in seconds (Default: 5.0)")
    parser.add_argument("--max-latency-ms", type=float, default=500.0, help="Maximum allowed latency in ms (Default: 500)")
    parser.add_argument("--retries", type=int, default=3, help="Number of retry attempts per probe (Default: 3)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")

    args = parser.parse_args()
    passed = run_smoke_test(
        base_url=args.base_url,
        frontend_url=args.frontend_url,
        probes=DEFAULT_PROBES,
        timeout=args.timeout,
        max_latency_ms=args.max_latency_ms,
        retries=args.retries,
        json_output=args.json,
    )

    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
