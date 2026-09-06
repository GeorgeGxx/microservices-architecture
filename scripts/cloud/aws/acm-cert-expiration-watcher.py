#!/usr/bin/env python3
"""
acm-cert-expiration-watcher.py

Enterprise AWS ACM SSL/TLS Certificate Expiration & Renewal Watcher.
Monitors AWS Certificate Manager (ACM) certificates across regions, detecting:
- Expired or soon-to-expire certificates (< 30 days)
- In-use status on Application Load Balancers (ALB) or CloudFront
- Automated DNS renewal eligibility

Author  : GeorgeGxx/DevOps
Version : v2.0.0 (Enterprise Microservices Edition)

Usage:
  # Check primary region with default 30-day warning threshold:
  python scripts/cloud/aws/acm-cert-expiration-watcher.py --region us-east-1

  # Multi-region certificate monitor with 45-day threshold:
  python scripts/cloud/aws/acm-cert-expiration-watcher.py --region all --warning-days 45

  # Strict mode for CI/CD or cron heartbeat (fail if in-use cert is expiring):
  python scripts/cloud/aws/acm-cert-expiration-watcher.py --region us-east-1 --strict --json
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


def audit_acm_in_region(
    session: boto3.Session,
    region: str,
    warning_days: int = 30
) -> Dict[str, Any]:
    """Audits ACM certificates in a given region."""
    acm = session.client("acm", region_name=region)
    now = datetime.now(timezone.utc)

    result: Dict[str, Any] = {
        "region": region,
        "total_certificates": 0,
        "expiring_soon_count": 0,
        "expired_count": 0,
        "certificates": []
    }

    try:
        paginator = acm.get_paginator("list_certificates")
        for page in paginator.paginate():
            for summary in page.get("CertificateSummaryList", []):
                arn = summary["CertificateArn"]
                domain = summary["DomainName"]
                result["total_certificates"] += 1

                # Describe certificate details
                try:
                    detail = acm.describe_certificate(CertificateArn=arn).get("Certificate", {})
                    status = detail.get("Status", "UNKNOWN")
                    in_use = len(detail.get("InUseBy", [])) > 0
                    not_after = detail.get("NotAfter")
                    renewal_status = detail.get("RenewalEligibility", "UNKNOWN")

                    days_remaining = None
                    is_expiring_soon = False
                    is_expired = False

                    if not_after:
                        days_remaining = (not_after - now).days
                        if days_remaining <= 0:
                            is_expired = True
                            result["expired_count"] += 1
                        elif days_remaining <= warning_days:
                            is_expiring_soon = True
                            result["expiring_soon_count"] += 1

                    cert_info = {
                        "arn": arn,
                        "domain": domain,
                        "status": status,
                        "in_use": in_use,
                        "days_remaining": days_remaining,
                        "is_expiring_soon": is_expiring_soon,
                        "is_expired": is_expired,
                        "renewal_eligibility": renewal_status,
                        "not_after": not_after.isoformat() if not_after else None
                    }
                    result["certificates"].append(cert_info)

                except ClientError:
                    pass

    except ClientError as e:
        result["error"] = str(e)

    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enterprise AWS DevSecOps: Monitor ACM SSL/TLS certificate expiration."
    )
    parser.add_argument("--region", default="us-east-1", help="Target AWS region or 'all'")
    parser.add_argument("--profile", default=None, help="AWS CLI profile")
    parser.add_argument("--warning-days", type=int, default=30, help="Days threshold for expiration alert (default: 30)")
    parser.add_argument("--strict", action="store_true", help="Exit code 1 if any in-use certificate is expired or expiring soon")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    session = get_session(args.profile)
    regions = get_available_regions(session) if args.region.lower() == "all" else [args.region]

    if not args.json:
        print(f"\n{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD} 🔒 AWS ACM SSL/TLS CERTIFICATE EXPIRATION WATCHER{Colors.RESET}")
        print(f" Warning Threshold: {args.warning_days} days | Regions: {', '.join(regions)}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    all_results: List[Dict[str, Any]] = []
    total_certs = 0
    total_expiring = 0
    total_expired = 0
    critical_in_use_expiring = 0

    for r in regions:
        res = audit_acm_in_region(session, r, warning_days=args.warning_days)
        all_results.append(res)
        total_certs += res["total_certificates"]
        total_expiring += res["expiring_soon_count"]
        total_expired += res["expired_count"]

        if not args.json:
            print(f"{Colors.BOLD}🌍 Region: {r} (Found {res['total_certificates']} Certs){Colors.RESET}")
            if not res["certificates"]:
                print(f"  {Colors.DIM}✨ No ACM certificates configured.{Colors.RESET}\n")
                continue

            for c in res["certificates"]:
                domain = c["domain"]
                days = c["days_remaining"]
                in_use_str = f"{Colors.GREEN}[IN-USE]{Colors.RESET}" if c["in_use"] else f"{Colors.DIM}[UNUSED]{Colors.RESET}"

                if c["is_expired"]:
                    status_badge = f"{Colors.RED}{Colors.BOLD}[EXPIRED]{Colors.RESET}"
                    if c["in_use"]:
                        critical_in_use_expiring += 1
                elif c["is_expiring_soon"]:
                    status_badge = f"{Colors.YELLOW}{Colors.BOLD}[EXPIRING IN {days}d]{Colors.RESET}"
                    if c["in_use"]:
                        critical_in_use_expiring += 1
                else:
                    status_badge = f"{Colors.GREEN}[OK - {days}d left]{Colors.RESET}"

                print(f"  • {status_badge} {in_use_str} {Colors.CYAN}{domain}{Colors.RESET}")
                print(f"    Renewal: {c['renewal_eligibility']} | ARN: {c['arn']}")

            print()

    if args.json:
        print(json.dumps({
            "results": all_results,
            "summary": {
                "total_certificates": total_certs,
                "expiring_soon": total_expiring,
                "expired": total_expired,
                "critical_in_use_expiring": critical_in_use_expiring
            }
        }, indent=2))
    else:
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f" Total Certificates Checked : {total_certs}")
        print(f" Expiring Soon (< {args.warning_days}d)       : {Colors.YELLOW if total_expiring > 0 else Colors.GREEN}{total_expiring}{Colors.RESET}")
        print(f" Expired Certificates       : {Colors.RED if total_expired > 0 else Colors.GREEN}{total_expired}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    if args.strict and critical_in_use_expiring > 0:
        print(f"{Colors.RED}❌ Strict check failed: Found {critical_in_use_expiring} in-use certificates expired or expiring within {args.warning_days} days.{Colors.RESET}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
