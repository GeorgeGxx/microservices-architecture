#!/usr/bin/env python3
"""Unified diagnostic engine and entry point for platform components, telemetry, and order access.

Consolidates:
  1. Component and service verification (Swagger / OpenAPI, Prometheus series, Grafana dashboards).
  2. Telemetry and metrics diagnostics (JVM metrics, funnel activity, Vault series, PromQL evaluations).
  3. Authenticated order-list retrieval via Keycloak.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

DEFAULT_ROUTER_URL = "http://127.0.0.1:8080"
DEFAULT_PROMETHEUS = "http://127.0.0.1:9090"
DEFAULT_GRAFANA = "http://127.0.0.1:3000"
DEFAULT_KEYCLOAK = "http://127.0.0.1:8181"
DEFAULT_FRONTEND = "http://127.0.0.1:5173"

SERVICE_ENDPOINTS = {
    "products-service": "http://127.0.0.1:8004",
    "orders-service": "http://127.0.0.1:8003",
    "inventory-service": "http://127.0.0.1:8001",
    "notification-service": "http://127.0.0.1:8002",
}
GRAFANA_DASHBOARDS = ["business-operations", "technical-security"]


# ==============================================================================
# Helper functions
# ==============================================================================

def normalize_loopback(url: str) -> str:
    """Normalize localhost references to IPv4 loopback 127.0.0.1."""
    if not url:
        return ""
    return url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")


def env_value(name: str, default: str) -> str:
    """Read configuration from environment variable or .env file."""
    value = os.getenv(name)
    if value:
        return value
    try:
        with open(".env", "r", encoding="utf-8") as env_file:
            for line in env_file:
                if line.startswith(f"{name}="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return default


def query_promql(prom_url: str, promql: str):
    """Execute a PromQL query against Prometheus API."""
    url = f"{prom_url}/api/v1/query?query=" + urllib.parse.quote(promql)
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("data", {}).get("result", [])
    except Exception as e:
        return [{"error": str(e)}]


# ==============================================================================
# Component Verification (from verify.py)
# ==============================================================================

def verify_swagger(router_url: str):
    """Verify Cosmo Router Supergraph Gateway and microservices Swagger/OpenAPI endpoints."""
    print("\n\033[96m[1/3] 🔌 VERIFYING COSMO ROUTER & MICROSERVICE SWAGGER/OPENAPI SPECS\033[0m")

    # 1. Verify Cosmo Router (GraphQL Gateway)
    try:
        req = urllib.request.Request(
            f"{router_url.rstrip('/')}/graphql",
            data=b'{"query": "{ __typename }"}',
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"  [\033[92mOK\033[0m] Cosmo Router Supergraph Gateway reachable at {router_url} (HTTP {resp.status})")
    except Exception as e:
        print(f"  [\033[93mWARN\033[0m] Cosmo Router Gateway at {router_url}: {e}")

    # 2. Verify individual Spring Boot Microservice Swagger UIs & OpenAPI v3 Specs
    for svc, base_url in SERVICE_ENDPOINTS.items():
        is_reachable = False
        swagger_url = f"{base_url}/swagger-ui.html"
        try:
            req = urllib.request.Request(swagger_url)
            with urllib.request.urlopen(req, timeout=2) as resp:
                print(f"  [\033[92mOK\033[0m] Swagger UI [{svc}]: reachable at {swagger_url} (HTTP {resp.status})")
                is_reachable = True
        except Exception:
            pass

        if is_reachable:
            doc_url = f"{base_url}/v3/api-docs"
            try:
                req = urllib.request.Request(doc_url)
                with urllib.request.urlopen(req, timeout=2) as resp:
                    doc = json.loads(resp.read().decode("utf-8"))
                    title = doc.get("info", {}).get("title", svc)
                    endpoints_count = len(doc.get("paths", {}))
                    print(f"  [\033[92mOK\033[0m] OpenAPI Spec [{svc}]: Title = '{title}', Endpoints = {endpoints_count}")
            except Exception as e:
                print(f"  [\033[93mWARN\033[0m] OpenAPI Spec [{svc}] at {doc_url}: {e}")
        else:
            # Check docker container status
            try:
                res = subprocess.run(
                    ["docker", "ps", "--filter", f"name={svc}", "--format", "{{.Status}}"],
                    capture_output=True,
                    text=True,
                    timeout=3,
                )
                status_out = res.stdout.strip()
                if "Up" in status_out:
                    print(f"  [\033[92mOK\033[0m] Service [{svc}]: Docker container active ({status_out.splitlines()[0]})")
                else:
                    print(f"  [\033[93mWARN\033[0m] Service [{svc}]: Port {base_url} not exposed on host and container status: {status_out or 'Not found'}")
            except Exception as ex:
                print(f"  [\033[93mWARN\033[0m] Service [{svc}] at {swagger_url}: {ex}")


def verify_metrics(prometheus_url: str):
    """Verify Prometheus active metric series and scrape coverage."""
    print("\n\033[96m[2/3] 📊 VERIFYING PROMETHEUS METRIC SCRAPERS & SERIES\033[0m")
    names_url = f"{prometheus_url}/api/v1/label/__name__/values"
    try:
        req = urllib.request.Request(names_url)
        with urllib.request.urlopen(req, timeout=5) as resp:
            all_metrics = json.loads(resp.read().decode("utf-8")).get("data", [])
            print(f"  [\033[92mOK\033[0m] Total active Prometheus metric names: {len(all_metrics)}")
    except Exception as e:
        print(f"  [\033[91mFAIL\033[0m] Prometheus unreachable at {prometheus_url}: {e}")
        return

    ecom_metrics = [m for m in all_metrics if any(k in m for k in ["ecommerce", "inventory", "notification", "idempotency"])]
    print(f"  [\033[92mOK\033[0m] Found {len(ecom_metrics)} domain-specific metrics:")
    for m in sorted(ecom_metrics)[:8]:
        q_url = f"{prometheus_url}/api/v1/query?query={m}"
        try:
            with urllib.request.urlopen(q_url, timeout=3) as q_resp:
                res = json.loads(q_resp.read().decode("utf-8")).get("data", {}).get("result", [])
                val = res[0].get("value", [0, 0])[1] if res else "No Series"
                print(f"    • {m:<40} ({len(res)} active series, latest = {val})")
        except Exception as err:
            print(f"    • {m:<40} (Error: {err})")


def verify_grafana(grafana_url: str):
    """Verify Grafana dashboards and configured panels."""
    print("\n\033[96m[3/3] 📈 VERIFYING GRAFANA DASHBOARDS & PANELS\033[0m")
    auth_header = "Basic " + base64.b64encode(b"admin:admin").decode("utf-8")
    for uid in GRAFANA_DASHBOARDS:
        url = f"{grafana_url}/api/dashboards/uid/{uid}"
        req = urllib.request.Request(url, headers={"Authorization": auth_header})
        try:
            with urllib.request.urlopen(req, timeout=4) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                title = data.get("dashboard", {}).get("title", uid)
                panels = len(data.get("dashboard", {}).get("panels", []))
                print(f"  [\033[92mOK\033[0m] Grafana loaded '{uid}': \"{title}\" with {panels} curated panels.")
        except Exception as e:
            print(f"  [\033[93mWARN\033[0m] Grafana dashboard '{uid}' check: {e}")


def run_components(target: str = "all", router_url: str = DEFAULT_ROUTER_URL, prometheus_url: str = DEFAULT_PROMETHEUS, grafana_url: str = DEFAULT_GRAFANA) -> int:
    """Execute component verifications based on target selection."""
    gw = normalize_loopback(router_url)
    prom = normalize_loopback(prometheus_url)
    graf = normalize_loopback(grafana_url)

    print("\n\033[96m================================================================================\033[0m")
    print(" \033[96m🔍 PLATFORM ECOSYSTEM VERIFICATION\033[0m")
    print(f" Target Mode: [{target.upper()}]")
    print("\033[96m================================================================================\033[0m")

    if target in ("all", "swagger"):
        verify_swagger(gw)
    if target in ("all", "metrics"):
        verify_metrics(prom)
    if target in ("all", "grafana"):
        verify_grafana(graf)

    print("\n\033[92m✨ Verification routine finished.\033[0m\n")
    return 0


# ==============================================================================
# Telemetry Diagnostics (from check.py)
# ==============================================================================

def check_jvm(prom_url: str):
    """Check JVM runtime metrics across registered Spring Boot applications."""
    print("\n\033[96m[1/3] ☕ CHECKING JVM RUNTIME TELEMETRY (Heap, Threads & Memory)\033[0m")
    queries = {
        "Heap Memory Used": 'jvm_memory_used_bytes{area="heap"}',
        "Live Threads": "jvm_threads_live_threads",
        "JVM CPU Usage": "jvm_cpu_recent_utilization_ratio",
    }
    for label, q in queries.items():
        results = query_promql(prom_url, q)
        if results and "error" in results[0]:
            print(f"  [\033[93mWARN\033[0m] {label:<25} Error: {results[0]['error']}")
            continue
        print(f"  [\033[92mOK\033[0m] {label:<25} ({len(results)} series reporting)")
        for r in results[:3]:
            app = r.get("metric", {}).get("application", r.get("metric", {}).get("job", "unknown"))
            val = r.get("value", [0, 0])[1]
            try:
                num_val = float(val)
                if "bytes" in q:
                    formatted_val = f"{num_val / (1024*1024):.1f} MB"
                elif "ratio" in q:
                    formatted_val = f"{num_val * 100:.1f}%"
                else:
                    formatted_val = f"{int(num_val)}"
            except Exception:
                formatted_val = str(val)
            print(f"      • {app:<25} = {formatted_val}")


def check_funnel_activity(prom_url: str):
    """Check observed funnel metrics in Prometheus."""
    print("\n\033[96m[2/3] 🛒 CHECKING OBSERVED E-COMMERCE FUNNEL ACTIVITY\033[0m")
    print("  Event counters are process-local and are not correlated by shopper session; no abandonment rate is inferred.")
    queries = [
        ("Cart add events in 1h", 'sum(increase(ecommerce_funnel_events_total{event_type="cart_add"}[1h])) or vector(0)'),
        ("Checkout start events in 1h", 'sum(increase(ecommerce_funnel_events_total{event_type="checkout_start"}[1h])) or vector(0)'),
        ("Payment step events in 1h", 'sum(increase(ecommerce_funnel_events_total{event_type="checkout_step",step="PAYMENT"}[1h])) or vector(0)'),
        ("Completed orders added in 1h", 'sum(max by (service) (clamp_min(delta(ecommerce_orders{status="COMPLETED",service="orders-service"}[1h]), 0))) or vector(0)'),
    ]
    for label, q in queries:
        res = query_promql(prom_url, q)
        if res and "error" in res[0]:
            print(f"  [\033[93mWARN\033[0m] {label:<25} Error: {res[0]['error']}")
            continue
        val = res[0].get("value", [0, 0])[1] if res else "NO DATA"
        try:
            val_fmt = f"{float(val):,.2f}"
        except Exception:
            val_fmt = str(val)
        print(f"  [\033[92mOK\033[0m] {label:<25} = {val_fmt}")


def check_vault(prom_url: str):
    """Check HashiCorp Vault metric series in Prometheus."""
    print("\n\033[96m[3/3] 🔒 CHECKING HASHICORP VAULT METRIC SERIES\033[0m")
    queries = [
        ("Vault Unsealed Status", "vault_core_unsealed"),
        ("Vault Scrape Status", 'up{job=~".*vault.*"}'),
    ]
    for label, q in queries:
        res = query_promql(prom_url, q)
        if res and "error" in res[0]:
            print(f"  [\033[93mWARN\033[0m] {label:<25} Error: {res[0]['error']}")
            continue
        val = res[0].get("value", [0, 0])[1] if res else "NO DATA"
        status_label = "HEALTHY / UNSEALED" if str(val) == "1" else f"Value: {val}"
        print(f"  [\033[92mOK\033[0m] {label:<25} = {status_label}")


def check_custom(prom_url: str, query_str: str):
    """Evaluate arbitrary custom PromQL query."""
    print(f"\n\033[96m[?] EVALUATING CUSTOM PROMQL QUERY: {query_str}\033[0m")
    res = query_promql(prom_url, query_str)
    if res and "error" in res[0]:
        print(f"  [\033[91mERROR\033[0m] {res[0]['error']}")
        return
    print(f"  [\033[92mOK\033[0m] Retrieved {len(res)} series:")
    for r in res[:5]:
        labels = r.get("metric", {})
        val = r.get("value", [0, 0])[1]
        print(f"    • {labels} ➔ {val}")


def run_telemetry(check: str = "all", query: str = "", prometheus_url: str = DEFAULT_PROMETHEUS) -> int:
    """Execute telemetry diagnostics."""
    prom = normalize_loopback(prometheus_url)

    print("\n\033[96m================================================================================\033[0m")
    print(" \033[96m🩺 ENTERPRISE TELEMETRY & PROMQL HEALTH CHECK\033[0m")
    print(f" Target Prometheus: {prom} | Mode: [{check.upper()}]")
    print("\033[96m================================================================================\033[0m")

    if check in ("all", "jvm"):
        check_jvm(prom)
    if check in ("all", "funnel", "abandonment"):
        if check == "abandonment":
            print("[INFO] --check abandonment is deprecated; reporting observed funnel activity instead.")
        check_funnel_activity(prom)
    if check in ("all", "vault"):
        check_vault(prom)
    if check == "promql":
        if not query:
            print("[\033[91mERROR\033[0m] Please provide --query \"<promql_expression>\"")
            return 1
        check_custom(prom, query)

    print("\n\033[92m✨ Diagnostics complete.\033[0m\n")
    return 0


# ==============================================================================
# Authenticated Order Check (from test_order.py)
# ==============================================================================

def run_orders_readonly(keycloak_url: str = None, frontend_url: str = None, client_secret: str = None) -> int:
    """Acquire a Keycloak token and read the current user's order list via frontend."""
    kc_url = normalize_loopback(keycloak_url or env_value("KEYCLOAK_URL", DEFAULT_KEYCLOAK)).rstrip("/")
    fe_url = normalize_loopback(frontend_url or env_value("FRONTEND_URL", DEFAULT_FRONTEND)).rstrip("/")
    secret = client_secret or env_value("KEYCLOAK_CLIENT_SECRET", "")

    if not secret:
        print("KEYCLOAK_CLIENT_SECRET is missing; run scripts/bootstrap-keycloak.ps1 first.", file=sys.stderr)
        return 1

    token_data = urllib.parse.urlencode({
        "client_id": "microservices_client",
        "client_secret": secret,
        "grant_type": "password",
        "username": "admin_user",
        "password": "admin",
    }).encode("utf-8")
    token_url = f"{kc_url}/realms/microservices-realm/protocol/openid-connect/token"
    token_request = urllib.request.Request(
        token_url,
        data=token_data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(token_request, timeout=8) as response:
            token = json.loads(response.read().decode("utf-8"))["access_token"]
    except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError) as error:
        print(f"Keycloak token acquisition failed at {token_url}: {error}", file=sys.stderr)
        return 1

    orders_url = f"{fe_url}/api/order"
    orders_request = urllib.request.Request(
        orders_url,
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(orders_request, timeout=8) as response:
            payload = json.loads(response.read().decode("utf-8"))
            count = len(payload) if isinstance(payload, list) else "response received"
            print(f"Authenticated order-list request succeeded: HTTP {response.status}; {count} orders; via {orders_url}")
            return 0
    except urllib.error.HTTPError as error:
        print(f"Orders API returned HTTP {error.code}: {error.read().decode('utf-8', errors='replace')}", file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f"Orders API connection failed at {orders_url}: {error}", file=sys.stderr)
        return 1


# ==============================================================================
# CLI Entry Point
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Unified read-only diagnostics for platform components, telemetry, and order access"
    )
    subparsers = parser.add_subparsers(dest="suite", required=True)

    components = subparsers.add_parser(
        "components", help="Check Router/Swagger, Prometheus series, or Grafana dashboards"
    )
    components.add_argument("--target", choices=["all", "swagger", "metrics", "grafana"], default="all")
    components.add_argument("--router-url", default=os.getenv("COSMO_ROUTER_URL", DEFAULT_ROUTER_URL))
    components.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", DEFAULT_PROMETHEUS))
    components.add_argument("--grafana-url", default=os.getenv("GRAFANA_URL", DEFAULT_GRAFANA))

    telemetry = subparsers.add_parser(
        "telemetry", help="Run JVM, observed-funnel, Vault, or custom PromQL diagnostics"
    )
    telemetry.add_argument("--check", choices=["all", "jvm", "funnel", "abandonment", "vault", "promql"], default="all")
    telemetry.add_argument("--query", default="")
    telemetry.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", DEFAULT_PROMETHEUS))

    orders = subparsers.add_parser(
        "orders-readonly", help="Acquire a Keycloak token and read the current user's order list"
    )
    orders.add_argument("--keycloak-url", default=None)
    orders.add_argument("--frontend-url", default=None)

    subparsers.add_parser(
        "all", help="Run all component and telemetry diagnostics; does not query orders"
    )

    args = parser.parse_args()

    if args.suite == "components":
        return run_components(
            target=args.target,
            router_url=args.router_url,
            prometheus_url=args.prometheus_url,
            grafana_url=args.grafana_url,
        )

    if args.suite == "telemetry":
        if args.check == "promql" and not args.query:
            parser.error("telemetry --check promql requires --query")
        return run_telemetry(
            check=args.check,
            query=args.query,
            prometheus_url=args.prometheus_url,
        )

    if args.suite == "orders-readonly":
        return run_orders_readonly(
            keycloak_url=args.keycloak_url,
            frontend_url=args.frontend_url,
        )

    if args.suite == "all":
        prom = os.getenv("PROMETHEUS_URL", DEFAULT_PROMETHEUS)
        c_status = run_components(target="all", prometheus_url=prom)
        t_status = run_telemetry(check="all", prometheus_url=prom)
        return 1 if (c_status != 0 or t_status != 0) else 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
