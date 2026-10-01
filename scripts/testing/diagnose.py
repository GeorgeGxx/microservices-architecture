#!/usr/bin/env python3
"""Unified entry point for read-only component, telemetry, and order diagnostics.

The focused check.py, verify.py, and test_order.py tools remain available as
standalone commands. This dispatcher runs them as subprocesses so it does not
import modules with command-line or network side effects.
"""

import argparse
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]


def run_script(script_name, arguments):
    command = [sys.executable, str(SCRIPT_DIR / script_name), *arguments]
    return subprocess.run(command, cwd=REPO_ROOT, check=False).returncode


def main():
    parser = argparse.ArgumentParser(
        description="Read-only diagnostics for platform components, telemetry, and order access"
    )
    subparsers = parser.add_subparsers(dest="suite", required=True)

    components = subparsers.add_parser(
        "components", help="Check Router/Swagger, Prometheus series, or Grafana dashboards"
    )
    components.add_argument("--target", choices=["all", "swagger", "metrics", "grafana"], default="all")
    components.add_argument("--router-url")
    components.add_argument("--prometheus-url")
    components.add_argument("--grafana-url")

    telemetry = subparsers.add_parser(
        "telemetry", help="Run JVM, cart-abandonment, Vault, or custom PromQL diagnostics"
    )
    telemetry.add_argument("--check", choices=["all", "jvm", "abandonment", "vault", "promql"], default="all")
    telemetry.add_argument("--query", default="")
    telemetry.add_argument("--prometheus-url")

    subparsers.add_parser(
        "orders-readonly", help="Acquire a Keycloak token and read the current user's order list"
    )
    subparsers.add_parser(
        "all", help="Run all component and telemetry diagnostics; does not query orders"
    )

    args = parser.parse_args()
    if args.suite == "components":
        forwarded = ["--target", args.target]
        for name, flag in (("router_url", "--router-url"), ("prometheus_url", "--prometheus-url"), ("grafana_url", "--grafana-url")):
            value = getattr(args, name)
            if value:
                forwarded.extend([flag, value])
        return run_script("verify.py", forwarded)

    if args.suite == "telemetry":
        if args.check == "promql" and not args.query:
            parser.error("telemetry --check promql requires --query")
        forwarded = ["--check", args.check]
        if args.query:
            forwarded.extend(["--query", args.query])
        if args.prometheus_url:
            forwarded.extend(["--prometheus-url", args.prometheus_url])
        return run_script("check.py", forwarded)

    if args.suite == "orders-readonly":
        return run_script("test_order.py", [])

    component_status = run_script("verify.py", ["--target", "all"])
    telemetry_status = run_script("check.py", ["--check", "all"])
    return 1 if component_status or telemetry_status else 0


if __name__ == "__main__":
    raise SystemExit(main())
