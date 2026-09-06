#!/usr/bin/env python3
"""
enforce-cloudwatch-retention.py

Enterprise AWS FinOps CloudWatch Log Retention Enforcer.
Scans CloudWatch Log Groups across regions, identifies log groups configured with
infinite retention ('Never Expire'), and updates them to a compliant retention period
(e.g., 14, 30, or 90 days) to prevent runaway storage billing.

Author  : GeorgeGxx/DevOps
Version : v2.0.0 (Enterprise Microservices Edition)

Usage:
  # Dry-run audit for log groups with infinite retention:
  python scripts/cloud/aws/enforce-cloudwatch-retention.py --region us-east-1

  # Apply 30-day retention to all unmanaged log groups:
  python scripts/cloud/aws/enforce-cloudwatch-retention.py --region us-east-1 --retention-days 30 --apply

  # Filter specific prefix (e.g. EKS microservices logs):
  python scripts/cloud/aws/enforce-cloudwatch-retention.py --prefix /aws/eks/ --retention-days 14 --apply
"""

import argparse
import json
import sys
from typing import Any, Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError, ProfileNotFound
except ImportError:
    print("❌ Error: boto3 is not installed. Run: pip install boto3", file=sys.stderr)
    sys.exit(1)


class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"


VALID_RETENTION_DAYS = [
    1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
]


def get_session(profile: Optional[str] = None) -> boto3.Session:
    """Initializes and returns a boto3 session with credential validation."""
    try:
        session = boto3.Session(profile_name=profile)
        sts = session.client("sts")
        sts.get_caller_identity()
        return session
    except ProfileNotFound:
        print(f"{Colors.RED}❌ Error: AWS Profile '{profile}' not found.{Colors.RESET}", file=sys.stderr)
        sys.exit(1)
    except (NoCredentialsError, ClientError) as e:
        print(f"{Colors.RED}❌ AWS Authentication failed: {e}{Colors.RESET}", file=sys.stderr)
        sys.exit(1)


def get_available_regions(session: boto3.Session) -> List[str]:
    """Retrieves all active AWS regions for the account."""
    ec2 = session.client("ec2", region_name="us-east-1")
    try:
        response = ec2.describe_regions(AllRegions=False)
        return sorted([r["RegionName"] for r in response["Regions"]])
    except ClientError:
        return ["us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-west-1", "eu-central-1"]


def audit_and_enforce_logs(
    session: boto3.Session,
    region: str,
    target_retention: int,
    prefix: Optional[str] = None,
    apply: bool = False
) -> Dict[str, Any]:
    """Audits log groups in a region and enforces retention policies."""
    logs = session.client("logs", region_name=region)
    result: Dict[str, Any] = {
        "region": region,
        "total_log_groups": 0,
        "never_expire_count": 0,
        "updated_count": 0,
        "log_groups": []
    }

    paginator = logs.get_paginator("describe_log_groups")
    kwargs = {}
    if prefix:
        kwargs["logGroupNamePrefix"] = prefix

    try:
        for page in paginator.paginate(**kwargs):
            for lg in page.get("logGroups", []):
                result["total_log_groups"] += 1
                name = lg["logGroupName"]
                current_retention = lg.get("retentionInDays")
                stored_bytes = lg.get("storedBytes", 0)
                stored_mb = round(stored_bytes / (1024 * 1024), 2)

                is_never_expire = current_retention is None
                needs_update = is_never_expire or (current_retention != target_retention)

                if is_never_expire:
                    result["never_expire_count"] += 1

                if needs_update:
                    item = {
                        "name": name,
                        "stored_mb": stored_mb,
                        "current_retention": "Never Expire" if is_never_expire else f"{current_retention} days",
                        "target_retention": f"{target_retention} days",
                        "updated": False
                    }

                    if apply:
                        try:
                            logs.put_retention_policy(
                                logGroupName=name,
                                retentionInDays=target_retention
                            )
                            item["updated"] = True
                            result["updated_count"] += 1
                        except ClientError as e:
                            item["error"] = str(e)

                    result["log_groups"].append(item)

    except ClientError as e:
        result["error"] = str(e)

    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enterprise AWS FinOps: Audit and enforce retention on CloudWatch Log Groups."
    )
    parser.add_argument("--region", default="us-east-1", help="Target AWS region or 'all'")
    parser.add_argument("--profile", default=None, help="AWS CLI profile")
    parser.add_argument("--retention-days", type=int, default=30, choices=VALID_RETENTION_DAYS,
                        help="Target retention in days (e.g. 14, 30, 90)")
    parser.add_argument("--prefix", default=None, help="Optional log group prefix filter (e.g. /aws/eks/)")
    parser.add_argument("--apply", action="store_true", help="Apply retention policy changes (default is dry-run)")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    session = get_session(args.profile)
    regions = get_available_regions(session) if args.region.lower() == "all" else [args.region]

    if not args.json:
        mode_str = f"{Colors.RED}LIVE ENFORCE (APPLY){Colors.RESET}" if args.apply else f"{Colors.GREEN}DRY-RUN (SIMULATION){Colors.RESET}"
        print(f"\n{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD} 📋 CLOUDWATCH LOG RETENTION FINOPS ENFORCER{Colors.RESET}")
        print(f" Mode: {mode_str} | Target: {args.retention_days} days | Regions: {', '.join(regions)}")
        if args.prefix:
            print(f" Filter Prefix: {args.prefix}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    all_results: List[Dict[str, Any]] = []
    total_groups = 0
    total_never_expire = 0
    total_updated = 0

    for r in regions:
        res = audit_and_enforce_logs(
            session, r,
            target_retention=args.retention_days,
            prefix=args.prefix,
            apply=args.apply
        )
        all_results.append(res)
        total_groups += res["total_log_groups"]
        total_never_expire += res["never_expire_count"]
        total_updated += res["updated_count"]

        if not args.json:
            print(f"{Colors.BOLD}🌍 Region: {r} (Scanned {res['total_log_groups']} Log Groups){Colors.RESET}")
            if not res["log_groups"]:
                print(f"  {Colors.GREEN}✅ All log groups already adhere to retention policies.{Colors.RESET}\n")
                continue

            for lg in res["log_groups"]:
                status = f"{Colors.GREEN}[UPDATED]{Colors.RESET}" if lg.get("updated") else f"{Colors.YELLOW}[NEEDS POLICY]{Colors.RESET}"
                print(f"  • {status} {Colors.CYAN}{lg['name']}{Colors.RESET} ({lg['stored_mb']} MB)")
                print(f"    Current: {lg['current_retention']} ➔ Target: {lg['target_retention']}")

            print()

    if args.json:
        print(json.dumps({
            "results": all_results,
            "summary": {
                "total_scanned": total_groups,
                "never_expire_count": total_never_expire,
                "updated_count": total_updated
            }
        }, indent=2))
    else:
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f" Total Groups Scanned : {total_groups}")
        print(f" 'Never Expire' Groups: {Colors.YELLOW}{total_never_expire}{Colors.RESET}")
        print(f" Groups Updated       : {Colors.GREEN}{total_updated}{Colors.RESET}")
        if not args.apply and total_never_expire > 0:
            print(f"{Colors.YELLOW}⚠️  Run with '--apply' to enforce {args.retention_days}-day retention across these groups.{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")


if __name__ == "__main__":
    main()
