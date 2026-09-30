#!/usr/bin/env python3
"""Estimate monthly AWS Terraform plan delta using a deliberately small USD catalog.

This is a review signal, not a quote: unsupported resources and variable usage
charges are listed so the estimate is never mistaken for a complete bill.
"""

import argparse
import json
import os
import sys

HOURS_PER_MONTH = 730
EC2_HOURLY = {
    "t3.medium": (0.0416, 0.0125),
    "t3.large": (0.0832, 0.0250),
    "m6i.large": (0.0960, 0.0380),
    "m6i.xlarge": (0.1920, 0.0760),
}
RDS_HOURLY = {
    "db.t3.micro": (0.017, 0.034),
    "db.t3.small": (0.034, 0.068),
    "db.t3.medium": (0.068, 0.136),
}


def monthly_cost(resource_type, values):
    if not values:
        return 0.0
    if resource_type == "aws_eks_cluster":
        return 73.0
    if resource_type == "aws_eks_node_group":
        scaling = values.get("scaling_config") or {}
        count = scaling.get("desired_size")
        instance_types = values.get("instance_types") or []
        if count is None or not instance_types or instance_types[0] not in EC2_HOURLY:
            return None
        on_demand, spot = EC2_HOURLY[instance_types[0]]
        hourly = spot if str(values.get("capacity_type", "ON_DEMAND")).upper() == "SPOT" else on_demand
        return hourly * HOURS_PER_MONTH * count
    if resource_type == "aws_db_instance":
        size = values.get("instance_class")
        if size not in RDS_HOURLY:
            return None
        single, multi = RDS_HOURLY[size]
        storage = float(values.get("allocated_storage") or 0) * 0.08
        return (multi if values.get("multi_az") else single) * HOURS_PER_MONTH + storage
    if resource_type == "aws_nat_gateway":
        return 32.40
    if resource_type == "aws_lb":
        return 16.20
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan_json", help="Terraform plan JSON produced by terraform show -json")
    parser.add_argument("--max-monthly-delta-usd", type=float, default=None, help="Optional ceiling for the estimated net monthly increase")
    args = parser.parse_args()
    if args.max_monthly_delta_usd is not None and args.max_monthly_delta_usd < 0:
        parser.error("--max-monthly-delta-usd cannot be negative")

    try:
        with open(args.plan_json, encoding="utf-8") as plan_file:
            plan = json.load(plan_file)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Unable to read Terraform plan JSON: {exc}", file=sys.stderr)
        return 2

    deltas = []
    unpriced = set()
    changes = plan.get("resource_changes") or []
    for change in changes:
        actions = change.get("change", {}).get("actions", [])
        if not actions or actions == ["no-op"] or actions == ["read"]:
            continue
        resource_type = change.get("type", "unknown")
        before = monthly_cost(resource_type, change.get("change", {}).get("before"))
        after = monthly_cost(resource_type, change.get("change", {}).get("after"))
        if before is None or after is None:
            unpriced.add(resource_type)
            continue
        delta = after - before
        if abs(delta) > 0.005:
            deltas.append((change.get("address", resource_type), delta))

    total = sum(delta for _, delta in deltas)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    lines = ["## Terraform FinOps plan delta (illustrative AWS catalog)", "", "| Resource | Estimated monthly USD change |", "|---|---:|"]
    for address, delta in deltas:
        lines.append(f"| `{address}` | `{delta:+.2f}` |")
    lines.extend(["", f"**Estimated net monthly change (priced resources only):** `${total:+.2f} USD`", "", "> This estimate omits usage-based charges and every resource type not listed below; it is not a quote."])
    if unpriced:
        lines.extend(["", "**Changed but unpriced resource types:** " + ", ".join(f"`{name}`" for name in sorted(unpriced))])
    report = "\n".join(lines) + "\n"
    print(report)
    if summary:
        with open(summary, "a", encoding="utf-8") as summary_file:
            summary_file.write("\n" + report)
    if args.max_monthly_delta_usd is not None and total > args.max_monthly_delta_usd:
        print(f"Estimated monthly increase ${total:.2f} exceeds ceiling ${args.max_monthly_delta_usd:.2f}.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
