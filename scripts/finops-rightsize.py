#!/usr/bin/env python3
"""Suggest Kubernetes CPU and memory request right-sizing from Prometheus.

Uses the observed 7-day peak, not averages, and leaves a safety margin. This is
advisory: validate against workload SLOs and seasonal traffic before applying.
Requires kube-state-metrics and cAdvisor metrics in the configured Prometheus.
"""

import argparse
import json
import sys
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import urlopen


QUERIES = {
    "cpu_peak": 'max by (namespace,pod,container) (max_over_time((rate(container_cpu_usage_seconds_total{container!="",container!="POD",image!=""}[5m]))[7d:5m]))',
    "cpu_request": 'max by (namespace,pod,container) (kube_pod_container_resource_requests{resource="cpu",unit="core"})',
    "memory_peak": 'max by (namespace,pod,container) (max_over_time(container_memory_working_set_bytes{container!="",container!="POD",image!=""}[7d]))',
    "memory_request": 'max by (namespace,pod,container) (kube_pod_container_resource_requests{resource="memory",unit="byte"})',
}


def query(base_url, expression):
    params = urlencode({"query": expression})
    request_url = f"{base_url.rstrip('/')}/api/v1/query?{params}"
    with urlopen(request_url, timeout=15) as response:
        payload = json.load(response)
    if payload.get("status") != "success":
        raise RuntimeError(payload.get("error", "Prometheus query failed"))
    return {
        tuple(item["metric"].get(k, "") for k in ("namespace", "pod", "container")): float(item["value"][1])
        for item in payload.get("data", {}).get("result", [])
    }


def cpu_millicores(value):
    return max(1, int(value * 1000 + 0.999))


def memory_mib(value):
    return max(1, int(value / (1024 * 1024) + 0.999))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prometheus-url", default="http://127.0.0.1:9090")
    parser.add_argument("--cpu-target", type=float, default=0.70, help="Target peak/request ratio for CPU (default: 0.70)")
    parser.add_argument("--memory-target", type=float, default=0.75, help="Target peak/request ratio for memory (default: 0.75)")
    args = parser.parse_args()
    if not 0 < args.cpu_target < 1 or not 0 < args.memory_target < 1:
        parser.error("targets must be between 0 and 1")

    try:
        metrics = {name: query(args.prometheus_url, expr) for name, expr in QUERIES.items()}
    except (URLError, TimeoutError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"FinOps right-sizing unavailable: {exc}", file=sys.stderr)
        print("Ensure Prometheus scrapes cAdvisor and kube-state-metrics; Docker Compose has no Kubernetes request metrics.", file=sys.stderr)
        return 2

    workloads = sorted(set(metrics["cpu_peak"]) | set(metrics["memory_peak"]))
    if not workloads:
        print("No container usage samples were returned for the last 7 days.", file=sys.stderr)
        return 2

    print("7-day peak utilization versus Kubernetes requests (advisory; inspect SLOs before applying)")
    print(f"{'NAMESPACE/POD/CONTAINER':64} {'CPU peak/request':>16} {'CPU suggestion':>16} {'MEM peak/request':>17} {'Memory suggestion':>19}")
    print("-" * 138)
    missing_requests = 0
    for key in workloads:
        namespace, pod, container = key
        cpu_peak = metrics["cpu_peak"].get(key)
        cpu_request = metrics["cpu_request"].get(key)
        mem_peak = metrics["memory_peak"].get(key)
        mem_request = metrics["memory_request"].get(key)
        cpu_ratio = cpu_peak / cpu_request if cpu_peak is not None and cpu_request else None
        mem_ratio = mem_peak / mem_request if mem_peak is not None and mem_request else None
        cpu_suggestion = "no request data"
        mem_suggestion = "no request data"
        if cpu_peak is not None and cpu_request:
            # Keep 30% headroom over the measured peak.
            proposed = cpu_millicores(cpu_peak / args.cpu_target)
            cpu_suggestion = f"{proposed}m" if cpu_ratio < args.cpu_target else "keep / investigate"
        else:
            missing_requests += 1
        if mem_peak is not None and mem_request:
            # Keep 25% headroom over peak working set and round to whole MiB.
            proposed = memory_mib(mem_peak / args.memory_target)
            mem_suggestion = f"{proposed}Mi" if mem_ratio < args.memory_target else "keep / investigate"
        else:
            missing_requests += 1
        display_name = f"{namespace}/{pod}/{container}"[-64:]
        cpu_display = f"{cpu_ratio:.0%}" if cpu_ratio is not None else "n/a"
        mem_display = f"{mem_ratio:.0%}" if mem_ratio is not None else "n/a"
        print(f"{display_name:64} {cpu_display:>16} {cpu_suggestion:>16} {mem_display:>17} {mem_suggestion:>19}")

    print("\nRecommendations use the observed peak plus safety headroom; they do not alter Kubernetes resources.")
    if missing_requests:
        print(f"{missing_requests} CPU/memory request measurements were missing; check kube-state-metrics and pod resource requests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
