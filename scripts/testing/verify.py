#!/usr/bin/env python3
"""
==============================================================================
Enterprise Microservices Platform Verification Super-Script (verify.py)
Consolidates:
  1. verify-swagger.ps1: Validates Swagger UI and OpenAPI v3 docs across services.
  2. verify_metrics.py: Scrapes Prometheus for active series and label names.
  3. verify_grafana.py: Inspects Grafana dashboards and panel health.
==============================================================================
Usage:
  python scripts/testing/verify.py --target all
  python scripts/testing/verify.py --target swagger
  python scripts/testing/verify.py --target metrics
  python scripts/testing/verify.py --target grafana
"""

import os
import sys
import json
import argparse
import base64
import urllib.request
import urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

DEFAULT_GATEWAY = "http://127.0.0.1:8080"
DEFAULT_PROMETHEUS = "http://127.0.0.1:9090"
DEFAULT_GRAFANA = "http://127.0.0.1:3000"

SERVICES = ["products-service", "orders-service", "inventory-service", "notification-service"]
GRAFANA_DASHBOARDS = ["business-operations", "technical-security"]

def verify_swagger(gateway_url):
    print("\n\033[96m[1/3] 🔌 VERIFYING SWAGGER UI & OPENAPI v3 SPECS\033[0m")
    url = f"{gateway_url}/swagger-ui.html"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"  [\033[92mOK\033[0m] Swagger UI reachable at {url} (HTTP {resp.status})")
    except Exception as e:
        print(f"  [\033[91mFAIL\033[0m] Swagger UI unreachable at {url}: {e}")

    for svc in SERVICES:
        doc_url = f"{gateway_url}/v3/api-docs/{svc}"
        try:
            req = urllib.request.Request(doc_url)
            with urllib.request.urlopen(req, timeout=4) as resp:
                doc = json.loads(resp.read().decode("utf-8"))
                title = doc.get("info", {}).get("title", svc)
                endpoints_count = len(doc.get("paths", {}))
                print(f"  [\033[92mOK\033[0m] OpenAPI Spec [{svc}]: Title = '{title}', Endpoints = {endpoints_count}")
        except Exception as e:
            print(f"  [\033[93mWARN\033[0m] OpenAPI Spec [{svc}]: {e}")

def verify_metrics(prometheus_url):
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

    ecom_metrics = [m for m in all_metrics if any(k in m for k in ['ecommerce', 'inventory', 'notification', 'idempotency'])]
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

def verify_grafana(grafana_url):
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

def main():
    parser = argparse.ArgumentParser(description="Enterprise Platform Verification Super-Script")
    parser.add_argument("--target", choices=["all", "swagger", "metrics", "grafana"], default="all", help="Target component to verify")
    parser.add_argument("--gateway-url", default=os.getenv("GATEWAY_URL", DEFAULT_GATEWAY), help="API Gateway URL")
    parser.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", DEFAULT_PROMETHEUS), help="Prometheus URL")
    parser.add_argument("--grafana-url", default=os.getenv("GRAFANA_URL", DEFAULT_GRAFANA), help="Grafana URL")

    args = parser.parse_args()

    gw = args.gateway_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")
    prom = args.prometheus_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")
    graf = args.grafana_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")

    print("\n\033[96m================================================================================\033[0m")
    print(" \033[96m🔍 PLATFORM ECOSYSTEM VERIFICATION (verify.py)\033[0m")
    print(f" Target Mode: [{args.target.upper()}]")
    print("\033[96m================================================================================\033[0m")

    if args.target in ("all", "swagger"):
        verify_swagger(gw)
    if args.target in ("all", "metrics"):
        verify_metrics(prom)
    if args.target in ("all", "grafana"):
        verify_grafana(graf)

    print("\n\033[92m✨ Verification routine finished.\033[0m\n")

if __name__ == "__main__":
    main()
