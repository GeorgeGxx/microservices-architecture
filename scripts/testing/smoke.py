#!/usr/bin/env python3
"""
==============================================================================
Enterprise Microservices Smoke Testing Super-Script (smoke.py)
Consolidates:
  1. smoke-test.ps1 (Level 3 E2E Integration & Keycloak Auth Prober)
  2. scripts/endpoint-smoke-test.py (Synthetic SLO & Actuator Health Validator)
==============================================================================
Usage:
  python scripts/testing/smoke.py
  python scripts/testing/smoke.py --base-url http://localhost:4200 --max-latency-ms 300
  python scripts/testing/smoke.py --json
  python scripts/testing/smoke.py --strict
"""

import os
import sys
import time
import uuid
import json
import argparse
import urllib.request
import urllib.error
import urllib.parse

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

DEFAULT_FRONTEND = "http://127.0.0.1:4200"
DEFAULT_KEYCLOAK = "http://127.0.0.1:8181"

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
            req = urllib.request.Request(f"{self.base_url}/actuator/health")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                lat = (time.time() - t0) * 1000
                status = data.get("status", "UNKNOWN")
                self.log_step("Frontend API Health (/actuator/health)", status == "UP", lat, f"Status: {status}")
        except Exception as e:
            self.log_step("Frontend API Health (/actuator/health)", False, (time.time() - t0) * 1000, f"Error: {e}")

        # 2. Keycloak JWT Authentication
        t0 = time.time()
        token = acquire_jwt(self.keycloak_url)
        lat = (time.time() - t0) * 1000
        self.log_step("Keycloak OIDC JWT Token Acquisition", bool(token), lat, f"Token: {token[:12]}... (Acquired)" if token else "Auth Failed")

        # 3. Apollo Router GraphQL through frontend Nginx
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
                self.log_step("Apollo Router GraphQL (/graphql)", ok, lat, "GraphQL response received")
        except Exception as e:
            self.log_step("Apollo Router GraphQL (/graphql)", False, (time.time() - t0) * 1000, f"Error: {e}")

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

def main():
    parser = argparse.ArgumentParser(description="Frontend, Apollo Router, and REST API smoke checks")
    parser.add_argument("--base-url", default=os.getenv("FRONTEND_URL", os.getenv("GATEWAY_URL", DEFAULT_FRONTEND)), help="Frontend base URL (Nginx proxies GraphQL and REST routes)")
    parser.add_argument("--keycloak-url", default=os.getenv("KEYCLOAK_URL", DEFAULT_KEYCLOAK), help="Keycloak IAM URL")
    parser.add_argument("--max-latency-ms", type=int, default=500, help="Maximum allowed latency SLO threshold in ms")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--strict", action="store_true", help="Exit with non-zero status code if any check fails")

    args = parser.parse_args()
    SmokeTester(args.base_url, args.keycloak_url, max_latency_ms=args.max_latency_ms, output_json=args.json, strict=args.strict).run()

if __name__ == "__main__":
    main()
