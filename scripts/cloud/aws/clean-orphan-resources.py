#!/usr/bin/env python3
"""
clean-orphan-resources.py

Enterprise AWS FinOps & Orphan Resource Cleaner.
Safely detects and purges unattached EBS volumes and unassociated Elastic IPs (EIPs)
across AWS regions to eliminate wasted cloud spending from orphaned microservices infrastructure.

Author  : GeorgeGxx/DevOps
Version : v2.0.0 (Enterprise Microservices Edition)

Usage:
  # Dry-run audit in us-east-1 (safe simulation):
  python scripts/cloud/aws/clean-orphan-resources.py --region us-east-1

  # Multi-region scan with JSON output:
  python scripts/cloud/aws/clean-orphan-resources.py --region all --json

  # Execute cleanup (live deletion) with confirmation:
  python scripts/cloud/aws/clean-orphan-resources.py --region us-east-1 --apply
"""

import argparse
import json
import sys
from datetime import datetime, timezone
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


# Cost estimates (approximate AWS US regions)
EBS_GP3_PER_GB_MONTH = 0.08
EIP_IDLE_PER_MONTH = 0.005 * 24 * 30.5  # ~$3.66/month per idle public IPv4


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


def audit_region(
    session: boto3.Session,
    region: str,
    apply_cleanup: bool = False,
    max_age_days: int = 0
) -> Dict[str, Any]:
    """Audits and optionally removes unattached EBS volumes and unassociated EIPs in a region."""
    ec2 = session.client("ec2", region_name=region)
    now = datetime.now(timezone.utc)

    result: Dict[str, Any] = {
        "region": region,
        "ebs_volumes": [],
        "elastic_ips": [],
        "total_wasted_ebs_gb": 0,
        "estimated_monthly_savings_usd": 0.0,
        "actions_taken": []
    }

    # 1. Audit unattached EBS volumes
    try:
        vols_resp = ec2.describe_volumes(Filters=[{"Name": "status", "Values": ["available"]}])
        for vol in vols_resp.get("Volumes", []):
            vol_id = vol["VolumeId"]
            size_gb = vol["Size"]
            vol_type = vol["VolumeType"]
            created_at = vol["CreateTime"]
            age_days = (now - created_at).days

            if max_age_days > 0 and age_days < max_age_days:
                continue

            name_tag = next((t["Value"] for t in vol.get("Tags", []) if t["Key"] == "Name"), "N/A")
            cost_est = size_gb * EBS_GP3_PER_GB_MONTH

            vol_info = {
                "volume_id": vol_id,
                "name": name_tag,
                "size_gb": size_gb,
                "type": vol_type,
                "age_days": age_days,
                "estimated_monthly_cost_usd": round(cost_est, 2),
                "deleted": False
            }

            if apply_cleanup:
                try:
                    ec2.delete_volume(VolumeId=vol_id)
                    vol_info["deleted"] = True
                    result["actions_taken"].append(f"Deleted EBS volume {vol_id} ({size_gb} GiB)")
                except ClientError as e:
                    vol_info["error"] = str(e)

            result["ebs_volumes"].append(vol_info)
            result["total_wasted_ebs_gb"] += size_gb
            result["estimated_monthly_savings_usd"] += cost_est

    except ClientError as e:
        result["ebs_error"] = str(e)

    # 2. Audit unassociated Elastic IPs
    try:
        eips_resp = ec2.describe_addresses()
        for eip in eips_resp.get("Addresses", []):
            if "AssociationId" not in eip:
                alloc_id = eip.get("AllocationId", "N/A")
                public_ip = eip.get("PublicIp", "N/A")
                eip_info = {
                    "allocation_id": alloc_id,
                    "public_ip": public_ip,
                    "estimated_monthly_cost_usd": round(EIP_IDLE_PER_MONTH, 2),
                    "released": False
                }

                if apply_cleanup and alloc_id != "N/A":
                    try:
                        ec2.release_address(AllocationId=alloc_id)
                        eip_info["released"] = True
                        result["actions_taken"].append(f"Released idle Elastic IP {public_ip} ({alloc_id})")
                    except ClientError as e:
                        eip_info["error"] = str(e)

                result["elastic_ips"].append(eip_info)
                result["estimated_monthly_savings_usd"] += EIP_IDLE_PER_MONTH

    except ClientError as e:
        result["eip_error"] = str(e)

    result["estimated_monthly_savings_usd"] = round(result["estimated_monthly_savings_usd"], 2)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enterprise AWS FinOps: Detect and clean unattached EBS volumes & idle Elastic IPs."
    )
    parser.add_argument("--region", default="us-east-1", help="Target AWS region or 'all'")
    parser.add_argument("--profile", default=None, help="AWS CLI profile")
    parser.add_argument("--apply", action="store_true", help="Execute deletion (default is DRY-RUN simulation)")
    parser.add_argument("--max-age-days", type=int, default=0, help="Only purge EBS volumes older than N days")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    session = get_session(args.profile)
    regions = get_available_regions(session) if args.region.lower() == "all" else [args.region]

    if not args.json:
        mode_str = f"{Colors.RED}LIVE CLEANUP (APPLY){Colors.RESET}" if args.apply else f"{Colors.GREEN}DRY-RUN (SIMULATION){Colors.RESET}"
        print(f"\n{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD} 🧹 AWS FINOPS ORPHAN RESOURCE CLEANER{Colors.RESET}")
        print(f" Mode: {mode_str} | Regions: {', '.join(regions)}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    all_results: List[Dict[str, Any]] = []
    total_savings = 0.0
    total_volumes = 0
    total_eips = 0

    for r in regions:
        res = audit_region(session, r, apply_cleanup=args.apply, max_age_days=args.max_age_days)
        all_results.append(res)
        total_savings += res["estimated_monthly_savings_usd"]
        total_volumes += len(res["ebs_volumes"])
        total_eips += len(res["elastic_ips"])

        if not args.json:
            print(f"{Colors.BOLD}🌍 Region: {r}{Colors.RESET}")
            if not res["ebs_volumes"] and not res["elastic_ips"]:
                print(f"  {Colors.DIM}✨ No orphan EBS volumes or idle Elastic IPs detected.{Colors.RESET}\n")
                continue

            if res["ebs_volumes"]:
                print(f"  📦 {Colors.YELLOW}Unattached EBS Volumes ({len(res['ebs_volumes'])}):{Colors.RESET}")
                for v in res["ebs_volumes"]:
                    action = f"{Colors.RED}[DELETED]{Colors.RESET}" if v.get("deleted") else f"{Colors.CYAN}[ORPHAN]{Colors.RESET}"
                    print(f"    • {action} {v['volume_id']} ({v['size_gb']} GiB, {v['type']}, age: {v['age_days']}d) - ~${v['estimated_monthly_cost_usd']}/mo")

            if res["elastic_ips"]:
                print(f"  🌐 {Colors.YELLOW}Unassociated Elastic IPs ({len(res['elastic_ips'])}):{Colors.RESET}")
                for ip in res["elastic_ips"]:
                    action = f"{Colors.RED}[RELEASED]{Colors.RESET}" if ip.get("released") else f"{Colors.CYAN}[IDLE]{Colors.RESET}"
                    print(f"    • {action} {ip['public_ip']} ({ip['allocation_id']}) - ~${ip['estimated_monthly_cost_usd']}/mo")

            print(f"  💵 Estimated Monthly Waste: {Colors.GREEN}${res['estimated_monthly_savings_usd']}{Colors.RESET}\n")

    if args.json:
        print(json.dumps({"results": all_results, "total_monthly_savings_usd": round(total_savings, 2)}, indent=2))
    else:
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f" Total Orphan EBS Volumes : {total_volumes}")
        print(f" Total Idle Elastic IPs   : {total_eips}")
        print(f" Total Estimated Savings  : {Colors.GREEN}${round(total_savings, 2)} USD / month{Colors.RESET}")
        if not args.apply and (total_volumes > 0 or total_eips > 0):
            print(f"{Colors.YELLOW}⚠️  Run with '--apply' to permanently purge these resources.{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")


if __name__ == "__main__":
    main()
