#!/usr/bin/env python3
r"""
==============================================================================
Enterprise End-to-End User Journey & MLOps Integration Test Runner
(test-e2e-journey.py)
==============================================================================
Validates the entire cross-service e-commerce and MLOps lifecycle:
  1. Service Health & Connectivity Check
  2. Keycloak IAM Token Acquisition (admin_user)
  3. Federated Catalog Query (Cosmo Router GraphQL)
  4. Order Placement (placeOrder mutation -> Orders Service -> Postgres)
  5. Order Delivery Fulfillment (deliverOrder mutation -> Kafka 'orders-topic')
  6. Kafka Order Event Delivery Verification
  7. Sales Capture Ingestion Verification (demand-sales-capture -> Parquet/Data)
  8. Demand Forecast Prediction Availability (demand-forecast-service -> /api/forecast)

Orchestrator Commands (platform-minikube.ps1):
  .\platform-minikube.ps1 journey
  .\platform-minikube.ps1 e2e
==============================================================================
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Terminal colors
CLR_CYAN = "\033[96m"
CLR_GREEN = "\033[92m"
CLR_YELLOW = "\033[93m"
CLR_RED = "\033[91m"
CLR_BOLD = "\033[1m"
CLR_RESET = "\033[0m"


def print_banner(text: str) -> None:
    print(f"\n{CLR_CYAN}{'=' * 80}{CLR_RESET}")
    print(f" {CLR_BOLD}{CLR_CYAN}🚀 {text}{CLR_RESET}")
    print(f"{CLR_CYAN}{'=' * 80}{CLR_RESET}")


def get_keycloak_secret() -> str:
    secret = os.getenv("KEYCLOAK_CLIENT_SECRET", "")
    if secret:
        return secret
    env_file = Path(".env")
    if env_file.exists():
        try:
            with env_file.open("r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("KEYCLOAK_CLIENT_SECRET="):
                        return line.strip().split("=", 1)[1].strip()
        except Exception:
            pass
    return "microservices_client_secret"


class E2EJourneyRunner:
    def __init__(
        self,
        router_url: str,
        keycloak_url: str,
        forecast_url: str,
        kafka_bootstrap: str,
        sales_csv: Path,
        sales_parquet: Path,
        capture_timeout: int = 90,
        timeout: int = 15,
        verbose: bool = False,
    ):
        self.router_url = router_url.rstrip("/")
        self.keycloak_url = keycloak_url.rstrip("/")
        self.forecast_url = forecast_url.rstrip("/")
        self.kafka_bootstrap = kafka_bootstrap
        self.sales_csv = sales_csv
        self.sales_parquet = sales_parquet
        self.capture_timeout = capture_timeout
        self.timeout = timeout
        self.verbose = verbose
        self.jwt_token: str = ""
        self.order_id: Optional[int] = None
        self.order_number: Optional[str] = None
        self.results: List[Dict[str, Any]] = []

    def log(self, step: str, message: str, status: str = "INFO") -> None:
        if status == "OK":
            badge = f"[{CLR_GREEN}PASS{CLR_RESET}]"
        elif status == "FAIL":
            badge = f"[{CLR_RED}FAIL{CLR_RESET}]"
        elif status == "WARN":
            badge = f"[{CLR_YELLOW}WARN{CLR_RESET}]"
        else:
            badge = f"[{CLR_CYAN}INFO{CLR_RESET}]"
        print(f"  {badge} {CLR_BOLD}{step}{CLR_RESET}: {message}")

    def run(self) -> bool:
        start_time = time.perf_counter()
        print_banner("FULL END-TO-END E-COMMERCE & MLOPS USER JOURNEY TEST")
        print(f"  * Cosmo Router:   {self.router_url}")
        print(f"  * Keycloak IAM:   {self.keycloak_url}")
        print(f"  * Forecast API:   {self.forecast_url}")
        print(f"  * Kafka Target:   {self.kafka_bootstrap}")

        pipeline_steps = [
            ("1. Health Connectivity", self._check_connectivity),
            ("2. Keycloak Auth", self._acquire_token),
            ("3. Browse Catalog", self._browse_catalog),
            ("4. Place Order", self._place_order),
            ("5. Deliver Order", self._deliver_order),
            ("6. Kafka Event Check", self._verify_kafka_event),
            ("7. Sales Capture Check", self._verify_sales_capture),
            ("8. Forecast Prediction", self._verify_forecast_service),
        ]

        overall_success = True
        for name, step_fn in pipeline_steps:
            t0 = time.perf_counter()
            try:
                success, details = step_fn()
                elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
                self.results.append({
                    "step": name,
                    "status": "PASS" if success else "FAIL",
                    "duration_ms": elapsed_ms,
                    "details": details,
                })
                if success:
                    self.log(name, f"{details} ({elapsed_ms}ms)", "OK")
                else:
                    self.log(name, f"{details} ({elapsed_ms}ms)", "FAIL")
                    overall_success = False
                    break
            except Exception as exc:
                elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
                self.results.append({
                    "step": name,
                    "status": "FAIL",
                    "duration_ms": elapsed_ms,
                    "details": str(exc),
                })
                self.log(name, f"Exception occurred: {exc} ({elapsed_ms}ms)", "FAIL")
                overall_success = False
                break

        total_elapsed = round(time.perf_counter() - start_time, 2)
        self._print_report(total_elapsed, overall_success)
        return overall_success

    # -------------------------------------------------------------------------
    # STEP 1: Connectivity Probes
    # -------------------------------------------------------------------------
    def _check_connectivity(self) -> Tuple[bool, str]:
        # Probe router GraphQL introspection or typename
        probe_query = json.dumps({"query": "{ __typename }"}).encode("utf-8")
        req = urllib.request.Request(
            f"{self.router_url}/graphql",
            data=probe_query,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if not data.get("data", {}).get("__typename"):
                    return False, "Router returned invalid GraphQL response"
        except Exception as e:
            return False, f"Router unreachable at {self.router_url}: {e}"

        # Probe Keycloak Realm
        kc_url = f"{self.keycloak_url}/realms/microservices-realm"
        try:
            with urllib.request.urlopen(kc_url, timeout=self.timeout) as resp:
                if resp.status != 200:
                    return False, f"Keycloak realm responded with HTTP {resp.status}"
        except Exception as e:
            return False, f"Keycloak unreachable at {self.keycloak_url}: {e}"

        return True, "Cosmo Router and Keycloak endpoints responsive"

    # -------------------------------------------------------------------------
    # STEP 2: Keycloak Token
    # -------------------------------------------------------------------------
    def _acquire_token(self) -> Tuple[bool, str]:
        token_endpoint = f"{self.keycloak_url}/realms/microservices-realm/protocol/openid-connect/token"
        client_secret = get_keycloak_secret()
        payload = urllib.parse.urlencode({
            "grant_type": "password",
            "client_id": "microservices_client",
            "client_secret": client_secret,
            "username": "admin_user",
            "password": "admin",
        }).encode("utf-8")

        req = urllib.request.Request(token_endpoint, data=payload, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                body = json.loads(resp.read().decode("utf-8"))
                self.jwt_token = body.get("access_token", "")
                if not self.jwt_token:
                    return False, "Response did not contain an access_token"
                return True, "Admin JWT acquired successfully"
        except urllib.error.HTTPError as he:
            err_msg = he.read().decode("utf-8", errors="replace")
            return False, f"HTTP {he.code}: {err_msg}"
        except Exception as exc:
            return False, f"Failed to acquire token: {exc}"

    # -------------------------------------------------------------------------
    # STEP 3: Catalog Query
    # -------------------------------------------------------------------------
    def _browse_catalog(self) -> Tuple[bool, str]:
        catalog_query = json.dumps({
            "query": "query { products { sku name price } }"
        }).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.jwt_token}",
        }
        req = urllib.request.Request(f"{self.router_url}/graphql", data=catalog_query, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                products = data.get("data", {}).get("products", [])
                if not products:
                    return False, "Catalog returned 0 products"
                return True, f"Found {len(products)} products in supergraph catalog"
        except Exception as exc:
            return False, f"Catalog query failed: {exc}"

    # -------------------------------------------------------------------------
    # STEP 4: Place Order
    # -------------------------------------------------------------------------
    def _place_order(self) -> Tuple[bool, str]:
        idempotency_key = str(uuid.uuid4())
        order_mutation = """
        mutation PlaceOrder($input: PlaceOrderInput!) {
          placeOrder(input: $input) {
            id
            orderNumber
            totalAmount
            orderStatus
          }
        }
        """
        payload = json.dumps({
            "query": order_mutation,
            "variables": {
                "input": {
                    "orderItems": [
                        {"sku": "LAPTOP-PRO", "price": 1499.99, "quantity": 1}
                    ],
                    "customerName": "E2E Test Agent",
                    "customerEmail": "e2e-test@novashop.local",
                    "shippingAddress": "100 DevSecOps Way",
                    "city": "Austin",
                    "postalCode": "78701",
                    "phone": "+1-555-0199",
                    "deliveryMethod": "STANDARD",
                    "paymentMethod": "CREDIT_CARD"
                }
            }
        }).encode("utf-8")

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.jwt_token}",
            "X-Idempotency-Key": idempotency_key,
        }
        req = urllib.request.Request(f"{self.router_url}/graphql", data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                errors = data.get("errors")
                if errors:
                    return False, f"GraphQL errors: {json.dumps(errors)}"
                order_data = data.get("data", {}).get("placeOrder")
                if not order_data:
                    return False, "No order data returned from placeOrder"
                self.order_id = int(order_data["id"])
                self.order_number = str(order_data["orderNumber"])
                return True, f"Created order {self.order_number} (ID: {self.order_id}, Status: {order_data.get('orderStatus')})"
        except Exception as exc:
            return False, f"Order placement failed: {exc}"

    # -------------------------------------------------------------------------
    # STEP 5: Deliver Order
    # -------------------------------------------------------------------------
    def _deliver_order(self) -> Tuple[bool, str]:
        if not self.order_id:
            return False, "No active order_id to deliver"

        deliver_mutation = """
        mutation DeliverOrder($id: ID!) {
          deliverOrder(id: $id) {
            id
            orderNumber
            orderStatus
          }
        }
        """
        payload = json.dumps({
            "query": deliver_mutation,
            "variables": {"id": self.order_id}
        }).encode("utf-8")

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.jwt_token}",
        }
        req = urllib.request.Request(f"{self.router_url}/graphql", data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                errors = data.get("errors")
                if errors:
                    return False, f"GraphQL errors: {json.dumps(errors)}"
                order_data = data.get("data", {}).get("deliverOrder")
                if not order_data or order_data.get("orderStatus") != "DELIVERED":
                    return False, f"Order status is not DELIVERED: {order_data}"
                return True, f"Order {self.order_number} transitioned to DELIVERED"
        except Exception as exc:
            return False, f"Order delivery failed: {exc}"

    # -------------------------------------------------------------------------
    # STEP 6: Verify Kafka Event Delivery
    # -------------------------------------------------------------------------
    def _verify_kafka_event(self) -> Tuple[bool, str]:
        # Attempt python kafka consumer inspection if available, or verify orders topic
        try:
            from kafka import KafkaConsumer
            consumer = KafkaConsumer(
                "orders-topic",
                bootstrap_servers=self.kafka_bootstrap.split(","),
                group_id=f"e2e-verification-{uuid.uuid4()}",
                auto_offset_reset="earliest",
                enable_auto_commit=False,
                consumer_timeout_ms=15000,
            )
            found = False
            for msg in consumer:
                try:
                    payload = json.loads(msg.value.decode("utf-8"))
                    if payload.get("orderNumber") == self.order_number:
                        found = True
                        break
                except Exception:
                    continue
            consumer.close()
            if found:
                return True, f"Found DELIVERED event for {self.order_number} in Kafka topic"
            return False, f"Kafka is reachable, but no event for {self.order_number} appeared within 15 seconds"
        except ImportError:
            return False, "kafka-python is required for Kafka event verification; install mlops/requirements.txt"
        except Exception as exc:
            return False, f"Kafka event verification failed at {self.kafka_bootstrap}: {exc}"

    # -------------------------------------------------------------------------
    # STEP 7: Verify Sales Capture Ingestion
    # -------------------------------------------------------------------------
    def _verify_sales_capture(self) -> Tuple[bool, str]:
        deadline = time.monotonic() + self.capture_timeout
        while time.monotonic() < deadline:
            if self.sales_csv.is_file():
                try:
                    with self.sales_csv.open(newline="", encoding="utf-8") as sales_file:
                        if any(row.get("order_number") == self.order_number for row in csv.DictReader(sales_file)):
                            return True, f"Order {self.order_number} persisted in {self.sales_csv.as_posix()}"
                except (OSError, csv.Error) as exc:
                    return False, f"Could not inspect sales CSV {self.sales_csv}: {exc}"

            if self.sales_parquet.is_dir():
                try:
                    import pandas as pd

                    captured = pd.read_parquet(self.sales_parquet, columns=["order_number"])
                    if captured["order_number"].astype(str).eq(self.order_number).any():
                        return True, f"Order {self.order_number} persisted in {self.sales_parquet.as_posix()}"
                except ImportError:
                    return False, "pandas and pyarrow are required to verify Parquet capture; use the MLOps venv"
                except (OSError, ValueError) as exc:
                    return False, f"Could not inspect sales Parquet {self.sales_parquet}: {exc}"
            time.sleep(2)
        return False, (
            f"Order {self.order_number} did not appear in CSV or Parquet capture within "
            f"{self.capture_timeout}s; check demand-sales-capture and its shared data volume"
        )

    # -------------------------------------------------------------------------
    # STEP 8: Verify Demand Forecast API
    # -------------------------------------------------------------------------
    def _verify_forecast_service(self) -> Tuple[bool, str]:
        # 1. Health check
        health_req = urllib.request.Request(f"{self.forecast_url}/health")
        try:
            with urllib.request.urlopen(health_req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("status") != "UP":
                    return False, f"Forecast API health status: {data}"
        except Exception as exc:
            return False, f"Forecast API health check failed at {self.forecast_url}: {exc}"

        # 2. Authenticated Forecast prediction check
        forecast_req = urllib.request.Request(
            f"{self.forecast_url}/api/forecast",
            headers={"Authorization": f"Bearer {self.jwt_token}"},
        )
        try:
            with urllib.request.urlopen(forecast_req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                horizon = data.get("horizonDays")
                products = data.get("products", [])
                run_id = data.get("modelRunId")
                if horizon != 7 or not products or not run_id:
                    return False, f"Forecast response is incomplete: horizon={horizon}, products={len(products)}, run_id={run_id}"
                return True, f"Forecast generated for {len(products)} SKUs (Horizon: {horizon}d, Run ID: {run_id})"
        except urllib.error.HTTPError as he:
            err_msg = he.read().decode("utf-8", errors="replace")
            return False, f"Forecast API error HTTP {he.code}: {err_msg}"
        except Exception as exc:
            return False, f"Failed to query forecast API: {exc}"

    # -------------------------------------------------------------------------
    # Summary Report
    # -------------------------------------------------------------------------
    def _print_report(self, total_seconds: float, passed: bool) -> None:
        print_banner("E2E JOURNEY EXECUTION REPORT & VERIFICATION AUDIT")
        print(f" {'Step':<30} | {'Status':<8} | {'Latency':<10} | {'Details'}")
        print(f" {'-' * 30}-|-{'-' * 8}-|-{'-' * 10}-|-{'-' * 25}")
        for r in self.results:
            color = CLR_GREEN if r["status"] == "PASS" else CLR_RED
            print(f" {r['step']:<30} | {color}{r['status']:<8}{CLR_RESET} | {r['duration_ms']:>7} ms | {r['details']}")
        print(f" {'-' * 30}-|-{'-' * 8}-|-{'-' * 10}-|-{'-' * 25}")
        print(f" Total Execution Time: {total_seconds} seconds")
        if passed:
            print(f" {CLR_BOLD}{CLR_GREEN}🏆 OVERALL RESULT: ALL E2E USER JOURNEY CHECKS PASSED{CLR_RESET}\n")
        else:
            print(f" {CLR_BOLD}{CLR_RED}💥 OVERALL RESULT: ONE OR MORE CHECKS FAILED{CLR_RESET}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--router-url", default=os.getenv("DEVSECOPS_ROUTER_URL", "http://127.0.0.1:8080"))
    parser.add_argument("--keycloak-url", default=os.getenv("DEVSECOPS_KEYCLOAK_URL", "http://127.0.0.1:8181"))
    parser.add_argument("--forecast-url", default=os.getenv("DEVSECOPS_FORECAST_URL", "http://127.0.0.1:8005"))
    parser.add_argument("--kafka-bootstrap", default=os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:29092,localhost:9092"))
    parser.add_argument("--sales-csv", type=Path, default=Path("mlops/data/sales.csv"))
    parser.add_argument("--sales-parquet", type=Path, default=Path("mlops/data/sales_parquet"))
    parser.add_argument("--capture-timeout", type=int, default=90)
    parser.add_argument("--timeout", type=int, default=15)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    runner = E2EJourneyRunner(
        router_url=args.router_url,
        keycloak_url=args.keycloak_url,
        forecast_url=args.forecast_url,
        kafka_bootstrap=args.kafka_bootstrap,
        sales_csv=args.sales_csv,
        sales_parquet=args.sales_parquet,
        capture_timeout=args.capture_timeout,
        timeout=args.timeout,
        verbose=args.verbose,
    )
    success = runner.run()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
