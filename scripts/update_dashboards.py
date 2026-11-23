r"""
==============================================================================
Grafana Dashboard Publisher & Funnel Telemetry (update_dashboards.py)
Validates and provisions the checked-in dashboards:
  1. Business Operations Dashboard: Revenue, conversion funnels, net orders,
     abandonment rates, and fulfillment velocity.
  2. Technical & Security Dashboard: RED metrics, p95/p99 latency, Istio mTLS,
     JVM heap, and edge rate-limiting telemetry.
  3. Demo Funnel Generator: Ingests CART_ADD events for conversion funnels.

Orchestrator Commands (platform-minikube.ps1):
  .\platform-minikube.ps1 dashboards [-Push]
  .\platform-minikube.ps1 funnel-demo [-Count 30] [-Category Electronics]
==============================================================================
"""
import json
import argparse
import base64
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ROOT_DIR = Path(__file__).resolve().parent.parent
BUSINESS_DASHBOARD = ROOT_DIR / 'observability' / 'grafana' / 'dashboards' / 'business-operations-dashboard.json'
TECHNICAL_DASHBOARD = ROOT_DIR / 'observability' / 'grafana' / 'dashboards' / 'technical-security-dashboard.json'
DASHBOARD_PATHS = (BUSINESS_DASHBOARD, TECHNICAL_DASHBOARD)


def update_dashboard_files():
    """Validate the checked-in dashboard JSON; it is the single source of truth."""
    for path in DASHBOARD_PATHS:
        try:
            dashboard = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"Invalid dashboard file {path}: {error}") from error
        if not isinstance(dashboard, dict) or not dashboard.get("uid") or not isinstance(dashboard.get("panels"), list):
            raise ValueError(f"Dashboard {path} must have a uid and a panels list")
        panel_ids = set()
        for panel in dashboard["panels"]:
            panel_id = panel.get("id")
            grid = panel.get("gridPos", {})
            if panel_id in panel_ids:
                raise ValueError(f"Dashboard {path} has duplicate panel id {panel_id}")
            panel_ids.add(panel_id)
            if not all(isinstance(grid.get(key), int) for key in ("x", "y", "w", "h")):
                raise ValueError(f"Dashboard {path} panel {panel_id} has an invalid gridPos")
            if grid["x"] < 0 or grid["y"] < 0 or grid["w"] < 1 or grid["h"] < 1 or grid["x"] + grid["w"] > 24:
                raise ValueError(f"Dashboard {path} panel {panel_id} falls outside the 24-column Grafana grid")
        print(f"Validated {path.name}: {len(panel_ids)} panels")


def push_dashboards(grafana_url: str = None) -> int:
    """Publish checked-in dashboards to GRAFANA_URL using configured credentials."""
    url = (grafana_url or os.getenv("GRAFANA_URL", "http://localhost:3000")).rstrip("/")
    token = os.getenv("GRAFANA_TOKEN")
    username = os.getenv("GRAFANA_USERNAME")
    password = os.getenv("GRAFANA_PASSWORD")
    if token:
        authorization = f"Bearer {token}"
    elif username and password:
        encoded = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
        authorization = f"Basic {encoded}"
    else:
        print("Error: --push requires GRAFANA_TOKEN or both GRAFANA_USERNAME and GRAFANA_PASSWORD.", file=sys.stderr)
        return 1

    if not url.startswith(("http://", "https://")):
        print(f"Error: Unsupported Grafana URL scheme: {url}", file=sys.stderr)
        return 1
    headers = {"Content-Type": "application/json", "Authorization": authorization}
    for path in DASHBOARD_PATHS:
        try:
            with open(path, "r", encoding="utf-8") as dashboard_file:
                dashboard = json.load(dashboard_file)
            payload = json.dumps({"dashboard": dashboard, "overwrite": True}).encode("utf-8")
            req = urllib.request.Request(f"{url}/api/dashboards/db", data=payload, headers=headers)
            # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
            with urllib.request.urlopen(req, timeout=10) as response:
                result = json.loads(response.read().decode("utf-8"))
                print(f"Pushed {path} to Grafana: {result.get('status')}")
        except Exception as e:
            print(f"Failed to push {path} to Grafana at {url}: {e}", file=sys.stderr)
            return 1

    # Remove dashboards that are now consolidated into the two audience-focused views.
    for uid, title in (
        ("grafana-alloy", "standalone Alloy"),
        ("mlops-forecast-operations", "standalone MLOps operations"),
    ):
        try:
            del_req = urllib.request.Request(f"{url}/api/dashboards/uid/{uid}", headers=headers, method="DELETE")
            # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
            with urllib.request.urlopen(del_req, timeout=10):
                print(f"Removed obsolete {title} dashboard from Grafana.")
        except urllib.error.HTTPError as error:
            if error.code != 404:
                print(f"Could not remove obsolete {title} dashboard: HTTP {error.code}.", file=sys.stderr)
                return 1
        except Exception as error:
            print(f"Could not remove obsolete {title} dashboard: {error}.", file=sys.stderr)
            return 1

    return 0


def emit_funnel_events(frontend_url: str, count: int, category: str, delay_ms: int, timeout_seconds: int) -> int:
    """Emit demo conversion funnel telemetry events (CART_ADD, CHECKOUT_START, CHECKOUT_STEP) synchronized across orders and analytics services."""
    base = frontend_url.rstrip("/")
    if not base.startswith(("http://", "https://")):
        print(f"Error: Unsupported frontend URL scheme: {base}", file=sys.stderr)
        return 1
    headers = {"Content-Type": "application/json", "User-Agent": "Grafana-Demo-Telemetry/1.0"}
    failures = []
    started = time.monotonic()
    effective_delay = max(delay_ms, 30) if delay_ms else 30  # respect Nginx edge rate limiter

    print(f"Sending {count} synchronized conversion funnel events to {base}")
    print(f"Category: {category} | Interval: {effective_delay} ms | Timeout: {timeout_seconds} s")

    for index in range(1, count + 1):
        # 1. CART_ADD (100% of shoppers)
        cart_endpoints = [
            (f"{base}/api/order/funnel", json.dumps({"eventType": "CART_ADD", "category": category, "step": "cart"}).encode("utf-8")),
            (f"{base}/api/v1/analytics/events", json.dumps({"event_type": "cart_add", "category": category, "step": "cart"}).encode("utf-8")),
        ]
        for endpoint, payload in cart_endpoints:
            request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
            try:
                # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
                with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                    response.read()
            except Exception as error:
                failures.append({"request": index, "endpoint": endpoint, "error": str(error), "status": getattr(error, "code", None)})

        # 2. CHECKOUT_START (~60% proceed to checkout)
        if index <= int(count * 0.60):
            start_endpoints = [
                (f"{base}/api/order/funnel", json.dumps({"eventType": "CHECKOUT_START", "category": category, "step": "checkout"}).encode("utf-8")),
                (f"{base}/api/v1/analytics/events", json.dumps({"event_type": "checkout_start", "category": category, "step": "checkout"}).encode("utf-8")),
            ]
            for endpoint, payload in start_endpoints:
                request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
                try:
                    # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
                    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                        response.read()
                except Exception as error:
                    failures.append({"request": index, "endpoint": endpoint, "error": str(error), "status": getattr(error, "code", None)})

        # 3. CHECKOUT_STEP PAYMENT (~45% reach payment step)
        if index <= int(count * 0.45):
            step_endpoints = [
                (f"{base}/api/order/funnel", json.dumps({"eventType": "CHECKOUT_STEP", "category": category, "step": "PAYMENT"}).encode("utf-8")),
                (f"{base}/api/v1/analytics/events", json.dumps({"event_type": "checkout_step", "category": category, "step": "PAYMENT"}).encode("utf-8")),
            ]
            for endpoint, payload in step_endpoints:
                request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
                try:
                    # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
                    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                        response.read()
                except Exception as error:
                    failures.append({"request": index, "endpoint": endpoint, "error": str(error), "status": getattr(error, "code", None)})

        time.sleep(effective_delay / 1000)

    print(f"Completed in {time.monotonic() - started:.2f}s: processed {count} event scenarios.")
    for failure in failures[:10]:
        status = f"HTTP {failure['status']}" if failure["status"] is not None else "request failed"
        print(f"  Request {failure['request']}: {status} — {failure['error']}", file=sys.stderr)
    if len(failures) > 10:
        print(f"  ... and {len(failures) - 10} more failure(s)", file=sys.stderr)
    if failures:
        print("Check frontend/Nginx and Orders Service, then inspect the Grafana funnel panels.", file=sys.stderr)
        return 1
    print("Demo events accepted. Allow the metrics pipeline to scrape them before checking Grafana.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate and publish versioned Grafana dashboards, or emit demo funnel telemetry."
    )
    # Direct flags (backward-compatible with python scripts/update_dashboards.py [--push])
    parser.add_argument("--push", action="store_true", help="Publish checked-in dashboards to Grafana using configured credentials")
    parser.add_argument("--grafana-url", default=None, help="Grafana base URL")

    # Subcommands (backward-compatible with grafana.py dashboards / funnel-demo)
    subparsers = parser.add_subparsers(dest="command")

    dash_cmd = subparsers.add_parser("dashboards", help="Validate the checked-in dashboards; use --push to publish")
    dash_cmd.add_argument("--push", action="store_true", help="Publish to Grafana using configured credentials")
    dash_cmd.add_argument("--grafana-url", default=None, help="Grafana base URL")

    funnel_cmd = subparsers.add_parser("funnel-demo", help="Emit CART_ADD demo events for Grafana funnel panels")
    funnel_cmd.add_argument("--frontend-url", default=os.getenv("FRONTEND_URL", "http://127.0.0.1:5173"), help="Frontend/Nginx URL")
    funnel_cmd.add_argument("--count", type=int, default=30, help="Number of demo events (1-1000; default: 30)")
    funnel_cmd.add_argument("--category", default="Electronics", help="Event category (default: Electronics)")
    funnel_cmd.add_argument("--delay-ms", type=int, default=100, help="Pause between events, ms (0-60000; default: 100)")
    funnel_cmd.add_argument("--timeout-seconds", type=int, default=10, help="HTTP timeout per event (1-120; default: 10)")

    args = parser.parse_args()

    if args.command == "funnel-demo":
        if not 1 <= args.count <= 1000:
            parser.error("--count must be between 1 and 1000")
        if not 0 <= args.delay_ms <= 60000:
            parser.error("--delay-ms must be between 0 and 60000")
        if not 1 <= args.timeout_seconds <= 120:
            parser.error("--timeout-seconds must be between 1 and 120")
        return emit_funnel_events(args.frontend_url, args.count, args.category, args.delay_ms, args.timeout_seconds)

    # Validate the checked-in dashboard JSON files (default action or 'dashboards' subcommand).
    try:
        update_dashboard_files()
    except ValueError as error:
        print(f"Dashboard validation failed: {error}", file=sys.stderr)
        return 1

    should_push = getattr(args, "push", False)
    if should_push:
        target_url = getattr(args, "grafana_url", None)
        return push_dashboards(target_url)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
