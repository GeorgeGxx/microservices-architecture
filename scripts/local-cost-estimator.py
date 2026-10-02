#!/usr/bin/env python3
"""
==============================================================================
Offline illustrative FinOps architecture estimator (not provider billing)
Supports:
  - 'minikube' (Local Intel/AMD Hardware vs AWS Cloud Savings Calculator)
  - 'staging' (AWS EKS Spot + Single-AZ RDS + Single NAT Gateway Profile)
  - 'prod' (AWS EKS On-Demand + Multi-AZ RDS + Multi-AZ NAT Profile)
Can parse live 'tfplan.json' or evaluate architectural baseline profiles.
==============================================================================
"""

import argparse
import json
import os
import sys
from typing import Dict, Any, List

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

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
        "hardware": "8 vCPUs allocated | 14 GB RAM | 60 GB NVMe Disk",
        "cloud_equivalent_cost": 309.80,
        "actual_cost": 0.00,
        "items": [
            {"component": "Kubernetes Control Plane", "detail": "Local Minikube (v1.39.0)", "monthly": 0.00, "cloud_equiv": 73.00},
            {"component": "Workload Compute Nodes", "detail": "Intel/AMD (8 vCPUs / 14GB RAM)", "monthly": 0.00, "cloud_equiv": 182.40},
            {"component": "Container Ingress & Mesh", "detail": "Local Istio Demo + Ingress", "monthly": 0.00, "cloud_equiv": 16.20},
            {"component": "Backing Storage & Logs", "detail": "60 GB Local NVMe Storage", "monthly": 0.00, "cloud_equiv": 4.80},
            {"component": "Network Data Transfer", "detail": "Loopback (localhost / 127.0.0.1)", "monthly": 0.00, "cloud_equiv": 35.00},
        ]
    },
    "dev": {
        "title": "AWS Dev Environment (Illustrative Low-Cost Profile)",
        "items": [
            {"component": "Amazon EKS Control Plane", "detail": "1x EKS Cluster", "monthly": 73.00},
            {"component": "EKS Managed Node Group", "detail": "2x t3.medium (SPOT instances)", "monthly": round(2 * 0.0125 * 730, 2)},
            {"component": "AWS NAT Gateway", "detail": "1x NAT Gateway (data transfer excluded)", "monthly": 32.40},
            {"component": "Application Load Balancer", "detail": "1x ingress load balancer", "monthly": 16.20},
        ]
    },
    "staging": {
        "title": "AWS Staging Environment (Cost-Optimized Pre-Production)",
        "items": [
            {"component": "Amazon EKS Control Plane", "detail": "Standard EKS Cluster (1x)", "monthly": 73.00},
            {"component": "EKS Managed Node Group", "detail": "2x t3.large (SPOT Instances)", "monthly": 36.50},
            {"component": "Amazon RDS PostgreSQL", "detail": "db.t3.small (Single-AZ + 20GB gp3)", "monthly": 26.42},
            {"component": "AWS NAT Gateway", "detail": "1x Single NAT Gateway (Cost Optimization)", "monthly": 32.40},
            {"component": "Application Load Balancer", "detail": "1x Public ALB", "monthly": 16.20},
        ]
    },
    "prod": {
        "title": "AWS Production Environment (High Availability Multi-AZ)",
        "items": [
            {"component": "Amazon EKS Control Plane", "detail": "Production EKS Cluster (1x)", "monthly": 73.00},
            {"component": "EKS Managed Node Group", "detail": "3x m6i.large (ON-DEMAND Instances)", "monthly": 210.24},
            {"component": "Amazon RDS PostgreSQL", "detail": "db.t3.medium (Multi-AZ + 100GB gp3)", "monthly": 107.28},
            {"component": "AWS NAT Gateways", "detail": "2x Multi-AZ NAT Gateways (HA Redundancy)", "monthly": 64.80},
            {"component": "Application Load Balancer", "detail": "1x Production ALB", "monthly": 16.20},
        ]
    }
}


def parse_tfplan(plan_path: str, env_name: str) -> List[Dict[str, Any]]:
    if not os.path.exists(plan_path):
        return DEFAULT_PROFILES.get(env_name, DEFAULT_PROFILES["staging"])["items"]

    try:
        with open(plan_path, "r", encoding="utf-8") as f:
            plan_data = json.load(f)
    except Exception as e:
        print(f"Warning: Could not parse {plan_path} ({e}). Using architectural baseline profile.")
        return DEFAULT_PROFILES.get(env_name, DEFAULT_PROFILES["staging"])["items"]

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
        monthly = round(hourly_rate * 730 * desired, 2)
        items.append({
            "component": "EKS Managed Node Group",
            "detail": f"{desired}x {itype} ({cap_type} instances)",
            "monthly": monthly
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
        compute_monthly = hourly_rate * 730
        storage_monthly = storage_gb * PRICING_CATALOG["ebs_gp3_per_gb"]
        total_rds = round(compute_monthly + storage_monthly, 2)

        items.append({
            "component": "Amazon RDS PostgreSQL",
            "detail": f"{iclass} ({'Multi-AZ' if multi_az else 'Single-AZ'} + {storage_gb}GB gp3)",
            "monthly": total_rds
        })

    # Detect NAT Gateways
    nat_changes = [r for r in resource_changes if r.get("type") == "aws_nat_gateway" and "delete" not in r.get("change", {}).get("actions", [])]
    if nat_changes:
        count = len(nat_changes)
        items.append({
            "component": "AWS NAT Gateway",
            "detail": f"{count}x NAT Gateway{'s' if count > 1 else ''}",
            "monthly": round(PRICING_CATALOG["nat_gateway"] * count, 2)
        })

    # Detect ALB
    alb_changes = [r for r in resource_changes if r.get("type") == "aws_lb" and "delete" not in r.get("change", {}).get("actions", [])]
    if alb_changes:
        count = len(alb_changes)
        items.append({
            "component": "Application Load Balancer",
            "detail": f"{count}x ALB (Ingress Gateway)",
            "monthly": round(PRICING_CATALOG["alb"] * count, 2)
        })

    return items if items else DEFAULT_PROFILES.get(env_name, DEFAULT_PROFILES["staging"])["items"]


def generate_reports(env_name: str, items: List[Dict[str, Any]], markdown_path: str = None, budget_usd: float = None):
    is_minikube = (env_name == "minikube")

    # Terminal Output
    print("\n" + "=" * 80)
    print(f"💰 FINOPS COST ESTIMATION REPORT: [{env_name.upper()}] (Local Air-Gapped)")
    print("=" * 80)

    if is_minikube:
        total_cloud_equiv = sum(item.get("cloud_equiv", 0.0) for item in items)
        print(f"Local Host: Intel/AMD (8+ cores) | 16+ GB RAM | 40 GB NVMe Storage")
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
        f"> Generated locally from illustrative architecture profiles; this is not live Kubernetes allocation or provider billing.",
        ""
    ]

    if is_minikube:
        total_cloud_equiv = sum(item.get("cloud_equiv", 0.0) for item in items)
        md_lines.extend([
            "| Component | Local Minikube Hardware Profile | Equivalent AWS Cloud Cost |",
            "| :--- | :--- | :--- |"
        ])
        for item in items:
            md_lines.append(f"| **{item['component']}** | `{item['detail']}` | `${item['cloud_equiv']:.2f}` / mo |")
        md_lines.extend([
            "",
            f"**Actual Local Cloud Bill:** `$0.00 USD / month`",
            f"**Estimated AWS Cloud Savings:** `~${total_cloud_equiv:.2f} USD / month` 🚀"
        ])
    else:
        total_monthly = sum(item.get("monthly", 0.0) for item in items)
        md_lines.extend([
            "| Infrastructure Component | Architecture Specification | Estimated Monthly Cost |",
            "| :--- | :--- | :--- |"
        ])
        for item in items:
            md_lines.append(f"| **{item['component']}** | `{item['detail']}` | `${item['monthly']:.2f}` / mo |")
        md_lines.extend([
            "",
            f"### **Total Estimated AWS Monthly Cost:** `${total_monthly:.2f} USD`",
            f"*Hourly Run Rate:* `${(total_monthly / 730):.4f} USD / hr`"
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
            print(f"[+] Appended FinOps breakdown to GITHUB_STEP_SUMMARY")
        except Exception as e:
            print(f"Notice: Could not write to GITHUB_STEP_SUMMARY: {e}")


def main():
    parser = argparse.ArgumentParser(description="Offline illustrative architecture estimate (not provider billing)")
    parser.add_argument("--env", choices=["minikube", "dev", "staging", "prod"], default="staging", help="Target environment")
    parser.add_argument("--plan", default=None, help="Path to terraform plan JSON (tfplan.json)")
    parser.add_argument("--markdown-out", default=None, help="Path to write Markdown report")
    parser.add_argument("--max-monthly-usd", type=float, default=None, help="Optional estimate ceiling in USD; exits 2 if the illustrative profile exceeds it")
    args = parser.parse_args()

    if args.max_monthly_usd is not None and args.max_monthly_usd <= 0:
        parser.error("--max-monthly-usd must be greater than zero")

    env = args.env

    if args.plan and os.path.exists(args.plan) and env != "minikube":
        items = parse_tfplan(args.plan, env)
    else:
        profile = DEFAULT_PROFILES.get(env, DEFAULT_PROFILES["staging"])
        items = profile["items"]

    generate_reports(env, items, args.markdown_out, args.max_monthly_usd)
    if args.max_monthly_usd is not None and env != "minikube" and sum(item.get("monthly", 0.0) for item in items) > args.max_monthly_usd:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
