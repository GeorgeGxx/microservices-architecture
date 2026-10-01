#!/usr/bin/env python3
"""Grafana-related project operations: dashboard generation and demo telemetry."""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_FRONTEND = os.getenv("FRONTEND_URL", "http://127.0.0.1:5173")


def generate_dashboards(push=False):
    """Run the existing dashboard generator; publishing remains opt-in."""
    command = [sys.executable, str(SCRIPT_DIR / "update_dashboards.py")]
    if push:
        command.append("--push")
    result = subprocess.run(command, cwd=REPO_ROOT, check=False)
    return result.returncode


def emit_funnel_events(frontend_url, count, category, delay_ms, timeout_seconds):
    endpoint = f"{frontend_url.rstrip('/')}/api/order/funnel"
    payload = json.dumps({"eventType": "CART_ADD", "category": category, "step": "cart"}).encode("utf-8")
    headers = {"Content-Type": "application/json", "User-Agent": "Grafana-Demo-Telemetry/1.0"}
    failures = []
    accepted = 0
    started = time.monotonic()

    print(f"Sending {count} demo CART_ADD events to {endpoint}")
    print(f"Category: {category} | Interval: {delay_ms} ms | Timeout: {timeout_seconds} s")
    for index in range(1, count + 1):
        request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                response.read()
                if 200 <= response.status < 300:
                    accepted += 1
                else:
                    failures.append({"request": index, "status": response.status, "error": "Unexpected response"})
        except urllib.error.HTTPError as error:
            failures.append({"request": index, "status": error.code, "error": str(error.reason)})
        except Exception as error:
            failures.append({"request": index, "status": None, "error": str(error)})

        if delay_ms and index < count:
            time.sleep(delay_ms / 1000)

    print(f"Completed in {time.monotonic() - started:.2f}s: {accepted}/{count} events accepted.")
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


def main():
    parser = argparse.ArgumentParser(description="Grafana dashboard and demo-telemetry tools")
    subparsers = parser.add_subparsers(dest="command", required=True)

    dashboards_parser = subparsers.add_parser("dashboards", help="Generate dashboard JSON files")
    dashboards_parser.add_argument("--push", action="store_true", help="Publish to Grafana using configured credentials")

    funnel_parser = subparsers.add_parser("funnel-demo", help="Emit CART_ADD demo events for Grafana funnel panels")
    funnel_parser.add_argument("--frontend-url", default=DEFAULT_FRONTEND, help="Frontend/Nginx URL (default: FRONTEND_URL or http://127.0.0.1:5173)")
    funnel_parser.add_argument("--count", type=int, default=30, help="Number of demo events (1-1000; default: 30)")
    funnel_parser.add_argument("--category", default="Electronics", help="Event category (default: Electronics)")
    funnel_parser.add_argument("--delay-ms", type=int, default=100, help="Pause between events, milliseconds (0-60000; default: 100)")
    funnel_parser.add_argument("--timeout-seconds", type=int, default=10, help="HTTP timeout per event (1-120; default: 10)")

    args = parser.parse_args()
    if args.command == "dashboards":
        return generate_dashboards(push=args.push)
    if not 1 <= args.count <= 1000:
        parser.error("--count must be between 1 and 1000")
    if not 0 <= args.delay_ms <= 60000:
        parser.error("--delay-ms must be between 0 and 60000")
    if not 1 <= args.timeout_seconds <= 120:
        parser.error("--timeout-seconds must be between 1 and 120")
    return emit_funnel_events(args.frontend_url, args.count, args.category, args.delay_ms, args.timeout_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
