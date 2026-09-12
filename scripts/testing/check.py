#!/usr/bin/env python3
"""
==============================================================================
Enterprise Telemetry & PromQL Diagnostics Super-Script (check.py)
Consolidates:
  1. check_jvm_metrics.py: Inspects JVM heap, GC pauses, and thread pools.
  2. check_abandonment.py & check_abandonment_panel.py: Cart abandonment formula.
  3. test_vault_metrics.py: Validates HashiCorp Vault metric series.
  4. test_query.py: Arbitrary PromQL evaluator.
==============================================================================
Usage:
  python scripts/testing/check.py --check all
  python scripts/testing/check.py --check jvm
  python scripts/testing/check.py --check abandonment
  python scripts/testing/check.py --check vault
  python scripts/testing/check.py --check promql --query "up"
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.parse
import urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

DEFAULT_PROMETHEUS = "http://127.0.0.1:9090"

def query_promql(prom_url, promql):
    url = f"{prom_url}/api/v1/query?query=" + urllib.parse.quote(promql)
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("data", {}).get("result", [])
    except Exception as e:
        return [{"error": str(e)}]

def check_jvm(prom_url):
    print("\n\033[96m[1/3] ☕ CHECKING JVM RUNTIME TELEMETRY (Heap, Threads & Memory)\033[0m")
    queries = {
        "Heap Memory Used": 'jvm_memory_used_bytes{area="heap"}',
        "Live Threads": 'jvm_threads_live_threads',
        "JVM CPU Usage": 'jvm_cpu_recent_utilization_ratio'
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

def check_abandonment(prom_url):
    print("\n\033[96m[2/3] 🛒 CHECKING E-COMMERCE CART ABANDONMENT FORMULA\033[0m")
    queries = [
        ("Cart Additions Total", 'sum(ecommerce_cart_additions_total)'),
        ("Completed Orders", 'sum(ecommerce_orders{status="COMPLETED"}) or sum(ecommerce_orders_total{status="COMPLETED"})'),
        ("Abandonment Rate %", 'clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status="COMPLETED"}) or sum(ecommerce_orders_total{status="COMPLETED"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)')
    ]
    for label, q in queries:
        res = query_promql(prom_url, q)
        if res and "error" in res[0]:
            print(f"  [\033[93mWARN\033[0m] {label:<25} Error: {res[0]['error']}")
            continue
        val = res[0].get("value", [0, 0])[1] if res else "NO DATA"
        try:
            val_fmt = f"{float(val):.2f}%" if "%" in label else f"{float(val):,.0f}"
        except Exception:
            val_fmt = str(val)
        print(f"  [\033[92mOK\033[0m] {label:<25} = {val_fmt}")

def check_vault(prom_url):
    print("\n\033[96m[3/3] 🔒 CHECKING HASHICORP VAULT METRIC SERIES\033[0m")
    queries = [
        ("Vault Unsealed Status", 'vault_core_unsealed'),
        ("Vault Scrape Status", 'up{job=~".*vault.*"}')
    ]
    for label, q in queries:
        res = query_promql(prom_url, q)
        if res and "error" in res[0]:
            print(f"  [\033[93mWARN\033[0m] {label:<25} Error: {res[0]['error']}")
            continue
        val = res[0].get("value", [0, 0])[1] if res else "NO DATA"
        status_label = "HEALTHY / UNSEALED" if str(val) == "1" else f"Value: {val}"
        print(f"  [\033[92mOK\033[0m] {label:<25} = {status_label}")

def check_custom(prom_url, query_str):
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

def main():
    parser = argparse.ArgumentParser(description="Enterprise Telemetry & PromQL Diagnostics Super-Script")
    parser.add_argument("--check", choices=["all", "jvm", "abandonment", "vault", "promql"], default="all", help="Diagnostic check to perform")
    parser.add_argument("--query", default="", help="Custom PromQL query string for --check promql")
    parser.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", DEFAULT_PROMETHEUS), help="Prometheus URL")

    args = parser.parse_args()
    prom = args.prometheus_url.replace("://localhost:", "://127.0.0.1:").replace("://localhost", "://127.0.0.1")

    print("\n\033[96m================================================================================\033[0m")
    print(" \033[96m🩺 ENTERPRISE TELEMETRY & PROMQL HEALTH CHECK (check.py)\033[0m")
    print(f" Target Prometheus: {prom} | Mode: [{args.check.upper()}]")
    print("\033[96m================================================================================\033[0m")

    if args.check in ("all", "jvm"):
        check_jvm(prom)
    if args.check in ("all", "abandonment"):
        check_abandonment(prom)
    if args.check in ("all", "vault"):
        check_vault(prom)
    if args.check == "promql":
        if not args.query:
            print("[\033[91mERROR\033[0m] Please provide --query \"<promql_expression>\"")
        else:
            check_custom(prom, args.query)

    print("\n\033[92m✨ Diagnostics complete.\033[0m\n")

if __name__ == "__main__":
    main()
