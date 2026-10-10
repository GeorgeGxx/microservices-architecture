#!/usr/bin/env python3
"""
==============================================================================
Offline illustrative FinOps architecture estimator (not provider billing)
Supports:
  - 'minikube' (Local Intel/AMD Hardware vs AWS Cloud Savings Calculator)
  - 'staging' (AWS EKS Spot + Single-AZ RDS + Single NAT Gateway Profile)
  - 'prod' (AWS EKS On-Demand + Multi-AZ RDS + Multi-AZ NAT Profile)
Can parse live 'tfplan.json', evaluate architectural baseline profiles, or
calculate incremental plan deltas (--plan-delta).
==============================================================================
"""

import argparse
import json
import os
import sys
from typing import Dict, Any, List, Optional, Tuple, Set
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import urlopen

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

HOURS_PER_MONTH = 730

RIGHTSIZE_QUERIES = {
    "cpu_peak": 'max by (namespace,pod,container) (max_over_time((rate(container_cpu_usage_seconds_total{container!="",container!="POD",image!=""}[5m]))[7d:5m]))',
    "cpu_request": 'max by (namespace,pod,container) (kube_pod_container_resource_requests{resource="cpu",unit="core"})',
    "memory_peak": 'max by (namespace,pod,container) (max_over_time(container_memory_working_set_bytes{container!="",container!="POD",image!=""}[7d]))',
    "memory_request": 'max by (namespace,pod,container) (kube_pod_container_resource_requests{resource="memory",unit="byte"})',
}

# Standard AWS US-East-1 baseline unit pricing (USD)
PRICING_CATALOG = {
    "eks_control_plane": 73.00,       # $0.10 / hour * 730 hours
    "nat_gateway": 32.40,             # $0.045 / hour * 730 hours (excl. data)
    "alb": 16.20,                     # $0.0225 / hour * 730 hours
    "ebs_gp3_per_gb": 0.08,           # $0.08 / GB-month
    "ec2_hourly": {
        "t3.medium": {"on_demand": 0.0416, "spot": 0.0125},
        "t3.large": {"on_demand": 0.0832, "spot": 0.0250},
        "m6i.large": {"on_demand": 0.0960, "spot": 0.0380},
        "m6i.xlarge": {"on_demand": 0.1920, "spot": 0.0760},
    },
    "rds_hourly": {
        "db.t3.micro": {"single_az": 0.017, "multi_az": 0.034},
        "db.t3.small": {"single_az": 0.034, "multi_az": 0.068},
        "db.t3.medium": {"single_az": 0.068, "multi_az": 0.136},
    }
}

DEFAULT_PROFILES = {
    "minikube": {
        "title": "Local Minikube Environment (Intel/AMD Hardware)",
        "hardware": "8 vCPUs allocated | 16 GiB RAM | 40 GB NVMe Disk",
        "cloud_equivalent_cost": 309.80,
        "actual_cost": 0.00,
        "items": [
            {"component": "Kubernetes Control Plane", "detail": "Local Minikube (v1.39.0)", "monthly": 0.00, "cloud_equiv": 73.00},
            {"component": "Workload Compute Nodes", "detail": "Intel/AMD (8 vCPUs / 16 GiB RAM)", "monthly": 0.00, "cloud_equiv": 182.40},
            {"component": "Container Ingress & Mesh", "detail": "Local Istio Demo + Ingress", "monthly": 0.00, "cloud_equiv": 16.20},
            {"component": "Backing Storage & Logs", "detail": "40 GB Local NVMe Storage", "monthly": 0.00, "cloud_equiv": 3.20},
            {"component": "Network Data Transfer", "detail": "Loopback (localhost / 127.0.0.1)", "monthly": 0.00, "cloud_equiv": 35.00},
        ]
    },
    "dev": {
        "title": "AWS Dev Environment (Illustrative Low-Cost Profile)",
        "items": [
            {"component": "Amazon EKS Control Plane", "detail": "1x EKS Cluster", "monthly": 73.00},
            {"component": "EKS Managed Node Group", "detail": "2x t3.medium (SPOT instances)", "monthly": round(2 * 0.0125 * 730, 2)},
            {"component": "Amazon RDS PostgreSQL", "detail": "db.t3.micro (Single-AZ + 20GB gp3)", "monthly": round(0.017 * 730 + 20 * 0.08, 2)},
            {"component": "Container Ingress (ALB)", "detail": "1x Application Load Balancer", "monthly": 16.20},
        ]
    },
    "staging": {
        "title": "AWS Staging Environment (Representative Architecture Profile)",
        "items": [
            {"component": "Amazon EKS Control Plane", "detail": "1x EKS Cluster (Multi-AZ Managed)", "monthly": 73.00},
            {"component": "EKS Managed Node Group", "detail": "3x t3.large (SPOT instances)", "monthly": round(3 * 0.0250 * 730, 2)},
            {"component": "Amazon RDS PostgreSQL", "detail": "db.t3.small (Single-AZ + 30GB gp3)", "monthly": round(0.034 * 730 + 30 * 0.08, 2)},
            {"component": "AWS NAT Gateway", "detail": "1x NAT Gateway (Cost-optimized)", "monthly": 32.40},
            {"component": "Application Load Balancer", "detail": "1x ALB (Ingress Gateway)", "monthly": 16.20},
        ]
    },
    "prod": {
        "title": "AWS Production Environment (High Availability Profile)",
        "items": [
            {"component": "Amazon EKS Control Plane", "detail": "1x EKS Cluster (HA Control Plane)", "monthly": 73.00},
            {"component": "EKS System Node Group", "detail": "2x m6i.large (On-Demand)", "monthly": round(2 * 0.0960 * 730, 2)},
            {"component": "EKS Workload Node Group", "detail": "4x m6i.xlarge (On-Demand)", "monthly": round(4 * 0.1920 * 730, 2)},
            {"component": "Amazon RDS PostgreSQL", "detail": "db.t3.medium (Multi-AZ + 100GB gp3)", "monthly": round(0.136 * 730 + 100 * 0.08, 2)},
            {"component": "AWS NAT Gateways", "detail": "3x NAT Gateways (Multi-AZ HA)", "monthly": round(32.40 * 3, 2)},
            {"component": "Application Load Balancers", "detail": "2x ALB (Public + Internal)", "monthly": round(16.20 * 2, 2)},
        ]
    }
}


def monthly_resource_cost(resource_type: str, values: Optional[Dict[str, Any]]) -> Optional[float]:
    """Calculate the monthly cost of an individual Terraform resource."""
    if not values:
        return 0.0
    if resource_type == "aws_eks_cluster":
        return PRICING_CATALOG["eks_control_plane"]
    if resource_type == "aws_eks_node_group":
        scaling = values.get("scaling_config") or {}
        count = scaling.get("desired_size")
        instance_types = values.get("instance_types") or []
        if count is None or not instance_types or instance_types[0] not in PRICING_CATALOG["ec2_hourly"]:
            return None
        rates = PRICING_CATALOG["ec2_hourly"][instance_types[0]]
        hourly = rates["spot"] if str(values.get("capacity_type", "ON_DEMAND")).upper() == "SPOT" else rates["on_demand"]
        return hourly * HOURS_PER_MONTH * count
    if resource_type == "aws_db_instance":
        size = values.get("instance_class")
        if size not in PRICING_CATALOG["rds_hourly"]:
            return None
        rates = PRICING_CATALOG["rds_hourly"][size]
        single = rates["single_az"]
        multi = rates["multi_az"]
        storage = float(values.get("allocated_storage") or 0) * PRICING_CATALOG["ebs_gp3_per_gb"]
        return (multi if values.get("multi_az") else single) * HOURS_PER_MONTH + storage
    if resource_type == "aws_nat_gateway":
        return PRICING_CATALOG["nat_gateway"]
    if resource_type == "aws_lb":
        return PRICING_CATALOG["alb"]
    return None


def evaluate_plan_delta(plan_path: str, max_monthly_delta_usd: Optional[float] = None) -> int:
    """Evaluate Terraform plan JSON delta and emit a structured markdown summary."""
    try:
        with open(plan_path, encoding="utf-8") as plan_file:
            plan = json.load(plan_file)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Unable to read Terraform plan JSON: {exc}", file=sys.stderr)
        return 2

    deltas: List[Tuple[str, float]] = []
    unpriced: Set[str] = set()
    changes = plan.get("resource_changes") or []
    for change in changes:
        actions = change.get("change", {}).get("actions", [])
        if not actions or actions == ["no-op"] or actions == ["read"]:
            continue
        resource_type = change.get("type", "unknown")
        before = monthly_resource_cost(resource_type, change.get("change", {}).get("before"))
        after = monthly_resource_cost(resource_type, change.get("change", {}).get("after"))
        if before is None or after is None:
            unpriced.add(resource_type)
            continue
        delta = after - before
        if abs(delta) > 0.005:
            deltas.append((change.get("address", resource_type), delta))

    total = sum(delta for _, delta in deltas)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    lines = [
        "## Terraform FinOps plan delta (illustrative AWS catalog)",
        "",
        "| Resource | Estimated monthly USD change |",
        "|---|---:|",
    ]
    for address, delta in deltas:
        lines.append(f"| `{address}` | `{delta:+.2f}` |")
    lines.extend([
        "",
        f"**Estimated net monthly change (priced resources only):** `${total:+.2f} USD`",
        "",
        "> This estimate omits usage-based charges and every resource type not listed below; it is not a quote.",
    ])
    if unpriced:
        lines.extend(["", "**Changed but unpriced resource types:** " + ", ".join(f"`{name}`" for name in sorted(unpriced))])
    report = "\n".join(lines) + "\n"
    print(report)

    if summary:
        try:
            with open(summary, "a", encoding="utf-8") as summary_file:
                summary_file.write("\n" + report)
        except Exception as e:
            print(f"Notice: Could not write to GITHUB_STEP_SUMMARY: {e}", file=sys.stderr)

    if max_monthly_delta_usd is not None and total > max_monthly_delta_usd:
        print(f"Estimated monthly increase ${total:.2f} exceeds ceiling ${max_monthly_delta_usd:.2f}.", file=sys.stderr)
        return 2
    return 0


def parse_tfplan(plan_path: str, env_name: str) -> List[Dict[str, Any]]:
    """Parse resources from a full terraform plan json export."""
    with open(plan_path, "r", encoding="utf-8") as f:
        plan_data = json.load(f)

    resource_changes = plan_data.get("resource_changes", [])
    items = []

    # Detect EKS Cluster
    eks_changes = [r for r in resource_changes if r.get("type") == "aws_eks_cluster" and "delete" not in r.get("change", {}).get("actions", [])]
    if eks_changes:
        items.append({"component": "Amazon EKS Control Plane", "detail": "Managed EKS Cluster", "monthly": PRICING_CATALOG["eks_control_plane"]})

    # Detect EKS Nodes
    node_changes = [r for r in resource_changes if r.get("type") == "aws_eks_node_group" and "delete" not in r.get("change", {}).get("actions", [])]
    for nc in node_changes:
        after = nc.get("change", {}).get("after", {}) or {}
        itypes = after.get("instance_types", ["t3.large"])
        itype = itypes[0] if itypes else "t3.large"
        scaling = after.get("scaling_config", {}) or {}
        desired = scaling.get("desired_size", 2)
        cap_type = after.get("capacity_type", "SPOT").upper()

        pricing_ec2 = PRICING_CATALOG["ec2_hourly"].get(itype, {"on_demand": 0.0832, "spot": 0.0250})
        hourly_rate = pricing_ec2["spot"] if cap_type == "SPOT" else pricing_ec2["on_demand"]
        monthly = round(hourly_rate * HOURS_PER_MONTH * desired, 2)
        items.append({
            "component": "EKS Managed Node Group",
            "detail": f"{desired}x {itype} ({cap_type} instances)",
            "monthly": monthly,
        })

    # Detect RDS
    rds_changes = [r for r in resource_changes if r.get("type") == "aws_db_instance" and "delete" not in r.get("change", {}).get("actions", [])]
    for rc in rds_changes:
        after = rc.get("change", {}).get("after", {}) or {}
        iclass = after.get("instance_class", "db.t3.small")
        multi_az = after.get("multi_az", False)
        storage_gb = after.get("allocated_storage", 20)
        mode = "multi_az" if multi_az else "single_az"

        pricing_rds = PRICING_CATALOG["rds_hourly"].get(iclass, {"single_az": 0.034, "multi_az": 0.068})
        hourly_rate = pricing_rds[mode]
        compute_monthly = hourly_rate * HOURS_PER_MONTH
        storage_monthly = storage_gb * PRICING_CATALOG["ebs_gp3_per_gb"]
        total_rds = round(compute_monthly + storage_monthly, 2)

        items.append({
            "component": "Amazon RDS PostgreSQL",
            "detail": f"{iclass} ({'Multi-AZ' if multi_az else 'Single-AZ'} + {storage_gb}GB gp3)",
            "monthly": total_rds,
        })

    # Detect NAT Gateways
    nat_changes = [r for r in resource_changes if r.get("type") == "aws_nat_gateway" and "delete" not in r.get("change", {}).get("actions", [])]
    if nat_changes:
        count = len(nat_changes)
        items.append({
            "component": "AWS NAT Gateway",
            "detail": f"{count}x NAT Gateway{'s' if count > 1 else ''}",
            "monthly": round(PRICING_CATALOG["nat_gateway"] * count, 2),
        })

    # Detect ALB
    alb_changes = [r for r in resource_changes if r.get("type") == "aws_lb" and "delete" not in r.get("change", {}).get("actions", [])]
    if alb_changes:
        count = len(alb_changes)
        items.append({
            "component": "Application Load Balancer",
            "detail": f"{count}x ALB (Ingress Gateway)",
            "monthly": round(PRICING_CATALOG["alb"] * count, 2),
        })

    return items if items else DEFAULT_PROFILES.get(env_name, DEFAULT_PROFILES["staging"])["items"]


def generate_reports(env_name: str, items: List[Dict[str, Any]], markdown_path: Optional[str] = None, budget_usd: Optional[float] = None):
    is_minikube = (env_name == "minikube")

    # Terminal Output
    print("\n" + "=" * 80)
    print(f"💰 FINOPS COST ESTIMATION REPORT: [{env_name.upper()}] (Local Air-Gapped)")
    print("=" * 80)

    if is_minikube:
        total_cloud_equiv = sum(item.get("cloud_equiv", 0.0) for item in items)
        print(f"Local Host: 8+ cores | 32+ GB RAM (Docker Desktop ~20 GiB / Minikube 16 GiB) | 40 GB NVMe")
        print(f"Actual Cloud Billing: $0.00 USD / month (100% Free Local Execution)")
        print(f"Equivalent AWS Cloud Cost: ~${total_cloud_equiv:.2f} USD / month")
        print(f"🏆 Local Monthly Savings: ~${total_cloud_equiv:.2f} USD / month\n")
        print(f"{'Component':<32} {'Local Configuration':<36} {'Equiv AWS Cost':<12}")
        print("-" * 80)
        for item in items:
            print(f"{item['component']:<32} {item['detail']:<36} ${item['cloud_equiv']:>9.2f}")
        print("-" * 80)
        print(f"{'TOTAL MONTHLY ESTIMATED CLOUD VALUE:':<68} ${total_cloud_equiv:>9.2f}")
    else:
        total_monthly = sum(item.get("monthly", 0.0) for item in items)
        print(f"Target Environment: AWS Cloud [{env_name.upper()}]")
        print(f"Pricing Model: Standard US-East-1 AWS On-Demand & Spot Catalog\n")
        print(f"{'Component':<32} {'Architecture Specification':<34} {'Monthly (USD)':<14}")
        print("-" * 80)
        for item in items:
            print(f"{item['component']:<32} {item['detail']:<34} ${item['monthly']:>10.2f}")
        print("-" * 80)
        print(f"{'TOTAL ESTIMATED MONTHLY AWS COST:':<66} ${total_monthly:>10.2f}")
        if budget_usd is not None:
            status = "WITHIN" if total_monthly <= budget_usd else "OVER"
            print(f"Monthly estimate budget: ${budget_usd:.2f} USD — {status} budget")

    print("=" * 80 + "\n")

    # Markdown Output
    md_lines = [
        f"## 💰 FinOps Cost Estimation Summary: `{env_name.upper()}`",
        "",
        "> [!NOTE]",
        "> Generated locally from illustrative architecture profiles; this is not live Kubernetes allocation or provider billing.",
        "",
    ]

    if is_minikube:
        total_cloud_equiv = sum(item.get("cloud_equiv", 0.0) for item in items)
        md_lines.extend([
            "| Component | Local Minikube Hardware Profile | Equivalent AWS Cloud Cost |",
            "| :--- | :--- | :--- |",
        ])
        for item in items:
            md_lines.append(f"| **{item['component']}** | `{item['detail']}` | `${item['cloud_equiv']:.2f}` / mo |")
        md_lines.extend([
            "",
            "**Actual Local Cloud Bill:** `$0.00 USD / month`",
            f"**Estimated AWS Cloud Savings:** `~${total_cloud_equiv:.2f} USD / month` 🚀",
        ])
    else:
        total_monthly = sum(item.get("monthly", 0.0) for item in items)
        md_lines.extend([
            "| Infrastructure Component | Architecture Specification | Estimated Monthly Cost |",
            "| :--- | :--- | :--- |",
        ])
        for item in items:
            md_lines.append(f"| **{item['component']}** | `{item['detail']}` | `${item['monthly']:.2f}` / mo |")
        md_lines.extend([
            "",
            f"### **Total Estimated AWS Monthly Cost:** `${total_monthly:.2f} USD`",
            f"*Hourly Run Rate:* `${(total_monthly / HOURS_PER_MONTH):.4f} USD / hr`",
        ])
        if budget_usd is not None:
            md_lines.extend(["", f"**Configured estimate ceiling:** `${budget_usd:.2f} USD / month` — {'within' if total_monthly <= budget_usd else 'over'} ceiling."])

    md_content = "\n".join(md_lines)

    if markdown_path:
        with open(markdown_path, "w", encoding="utf-8") as f:
            f.write(md_content)
        print(f"[+] Markdown report written to: {markdown_path}")

    # Append to GitHub Step Summary if running in CI
    gh_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if gh_summary and os.path.exists(gh_summary):
        try:
            with open(gh_summary, "a", encoding="utf-8") as f:
                f.write("\n\n" + md_content + "\n")
            print("[+] Appended FinOps breakdown to GITHUB_STEP_SUMMARY")
        except Exception as e:
            print(f"Notice: Could not write to GITHUB_STEP_SUMMARY: {e}")


def query_prometheus_rightsize(base_url: str, expression: str) -> Dict[Tuple[str, str, str], float]:
    """Execute PromQL expression and parse Kubernetes namespace/pod/container metrics."""
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


def cpu_millicores(value: float) -> int:
    """Convert core value to whole millicores with ceiling rounding."""
    return max(1, int(value * 1000 + 0.999))


def memory_mib(value: float) -> int:
    """Convert bytes value to whole MiB with ceiling rounding."""
    return max(1, int(value / (1024 * 1024) + 0.999))


def evaluate_rightsizing(prometheus_url: str = "http://127.0.0.1:9090", cpu_target: float = 0.70, memory_target: float = 0.75) -> int:
    """Calculate and format Kubernetes CPU/memory request right-sizing suggestions from Prometheus."""
    if not 0 < cpu_target < 1 or not 0 < memory_target < 1:
        print("Error: targets must be between 0 and 1", file=sys.stderr)
        return 2

    try:
        metrics = {name: query_prometheus_rightsize(prometheus_url, expr) for name, expr in RIGHTSIZE_QUERIES.items()}
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
            # Keep safety headroom over the measured peak.
            proposed = cpu_millicores(cpu_peak / cpu_target)
            cpu_suggestion = f"{proposed}m" if cpu_ratio < cpu_target else "keep / investigate"
        else:
            missing_requests += 1
        if mem_peak is not None and mem_request:
            # Keep safety headroom over peak working set and round to whole MiB.
            proposed = memory_mib(mem_peak / memory_target)
            mem_suggestion = f"{proposed}Mi" if mem_ratio < memory_target else "keep / investigate"
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


def main():
    parser = argparse.ArgumentParser(
        description="Unified FinOps architecture cost estimator, plan delta evaluator, and Kubernetes right-sizing advisory."
    )
    # Direct flags for backward-compatible pipeline execution
    parser.add_argument("--env", choices=["minikube", "dev", "staging", "prod"], default="staging", help="Target environment profile")
    parser.add_argument("--plan", default=None, help="Path to full terraform plan JSON (tfplan.json)")
    parser.add_argument("--plan-delta", default=None, help="Path to terraform plan JSON to calculate incremental monthly USD delta")
    parser.add_argument("--max-monthly-delta-usd", type=float, default=None, help="Ceiling for the net monthly increase when using --plan-delta")
    parser.add_argument("--markdown-out", default=None, help="Path to write Markdown report")
    parser.add_argument("--max-monthly-usd", type=float, default=None, help="Optional estimate ceiling in USD for profile/plan evaluation")
    parser.add_argument("--rightsize", action="store_true", help="Run 7-day Kubernetes CPU/memory right-sizing advisory")
    parser.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", "http://127.0.0.1:9090"), help="Prometheus URL for right-sizing")
    parser.add_argument("--cpu-target", type=float, default=0.70, help="Target peak/request ratio for CPU (default: 0.70)")
    parser.add_argument("--memory-target", type=float, default=0.75, help="Target peak/request ratio for memory (default: 0.75)")

    # Subcommands
    subparsers = parser.add_subparsers(dest="command")

    estimate_cmd = subparsers.add_parser("estimate", help="Run offline architecture cost estimate")
    estimate_cmd.add_argument("--env", choices=["minikube", "dev", "staging", "prod"], default="staging")
    estimate_cmd.add_argument("--plan", default=None)
    estimate_cmd.add_argument("--markdown-out", default=None)
    estimate_cmd.add_argument("--max-monthly-usd", type=float, default=None)

    delta_cmd = subparsers.add_parser("plan-delta", help="Evaluate incremental monthly USD delta from terraform show -json")
    delta_cmd.add_argument("plan_file", help="Path to terraform plan JSON")
    delta_cmd.add_argument("--max-monthly-delta-usd", type=float, default=None)

    rightsize_cmd = subparsers.add_parser("rightsize", help="Suggest Kubernetes CPU/memory request right-sizing from Prometheus")
    rightsize_cmd.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", "http://127.0.0.1:9090"))
    rightsize_cmd.add_argument("--cpu-target", type=float, default=0.70)
    rightsize_cmd.add_argument("--memory-target", type=float, default=0.75)

    args = parser.parse_args()

    # Subcommand dispatch
    if args.command == "rightsize" or args.rightsize:
        prom_url = getattr(args, "prometheus_url", "http://127.0.0.1:9090")
        cpu_t = getattr(args, "cpu_target", 0.70)
        mem_t = getattr(args, "memory_target", 0.75)
        return evaluate_rightsizing(prom_url, cpu_t, mem_t)

    if args.command == "plan-delta":
        plan_f = getattr(args, "plan_file", None)
        max_d = getattr(args, "max_monthly_delta_usd", None)
        if max_d is not None and max_d < 0:
            parser.error("--max-monthly-delta-usd cannot be negative")
        return evaluate_plan_delta(plan_f, max_d)

    # Direct plan delta flag
    if args.plan_delta:
        if args.max_monthly_delta_usd is not None and args.max_monthly_delta_usd < 0:
            parser.error("--max-monthly-delta-usd cannot be negative")
        return evaluate_plan_delta(args.plan_delta, args.max_monthly_delta_usd)

    if args.max_monthly_usd is not None and args.max_monthly_usd <= 0:
        parser.error("--max-monthly-usd must be greater than zero")

    env = getattr(args, "env", "staging")
    plan = getattr(args, "plan", None)
    md_out = getattr(args, "markdown_out", None)
    max_usd = getattr(args, "max_monthly_usd", None)

    if plan and os.path.exists(plan) and env != "minikube":
        items = parse_tfplan(plan, env)
    else:
        profile = DEFAULT_PROFILES.get(env, DEFAULT_PROFILES["staging"])
        items = profile["items"]

    generate_reports(env, items, md_out, max_usd)
    if max_usd is not None and env != "minikube" and sum(item.get("monthly", 0.0) for item in items) > max_usd:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
