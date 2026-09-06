#!/usr/bin/env python3
"""
audit-iam-credentials.py

Enterprise AWS DevSecOps IAM Credential & Access Key Auditor.
Audits IAM users against the CIS AWS Foundations Benchmark:
- Access keys older than 90 days (rotation requirement)
- Inactive access keys not used for >90 days
- Console users without Multi-Factor Authentication (MFA)
- Unused credentials posing security risks

Author  : GeorgeGxx/DevOps
Version : v2.0.0 (Enterprise Microservices Edition)

Usage:
  # Scan IAM credentials with default 90-day threshold:
  python scripts/cloud/aws/audit-iam-credentials.py

  # Custom key age and JSON report:
  python scripts/cloud/aws/audit-iam-credentials.py --max-key-age 60 --json

  # Strict mode (fail CI/CD exit code 1 if critical violations found):
  python scripts/cloud/aws/audit-iam-credentials.py --strict
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


def audit_iam(
    session: boto3.Session,
    max_key_age_days: int = 90,
    inactive_days_threshold: int = 90
) -> Dict[str, Any]:
    """Audits IAM users, access keys, and MFA posture."""
    iam = session.client("iam")
    now = datetime.now(timezone.utc)

    report: Dict[str, Any] = {
        "users_scanned": 0,
        "total_active_keys": 0,
        "aged_keys_count": 0,
        "inactive_keys_count": 0,
        "mfa_missing_count": 0,
        "findings": []
    }

    paginator = iam.get_paginator("list_users")
    for page in paginator.paginate():
        for user in page.get("Users", []):
            username = user["UserName"]
            report["users_scanned"] += 1
            user_findings: List[Dict[str, Any]] = []

            # 1. Check MFA status for users with console access
            has_mfa = False
            try:
                mfa_devices = iam.list_mfa_devices(UserName=username).get("MFADevices", [])
                has_mfa = len(mfa_devices) > 0
            except ClientError:
                pass

            # Check if login profile exists (console password enabled)
            has_console_password = False
            try:
                iam.get_login_profile(UserName=username)
                has_console_password = True
            except iam.exceptions.NoSuchEntityException:
                has_console_password = False
            except ClientError:
                pass

            if has_console_password and not has_mfa:
                report["mfa_missing_count"] += 1
                user_findings.append({
                    "type": "MFA_MISSING",
                    "severity": "HIGH",
                    "description": "User has AWS Management Console access without Multi-Factor Authentication (MFA)"
                })

            # 2. Check Access Keys
            try:
                keys = iam.list_access_keys(UserName=username).get("AccessKeyMetadata", [])
                for k in keys:
                    key_id = k["AccessKeyId"]
                    status = k["Status"]
                    created_at = k["CreateDate"]
                    age_days = (now - created_at).days

                    if status != "Active":
                        continue

                    report["total_active_keys"] += 1

                    # Check key age
                    if age_days > max_key_age_days:
                        report["aged_keys_count"] += 1
                        user_findings.append({
                            "type": "KEY_AGED",
                            "severity": "HIGH",
                            "key_id": key_id,
                            "age_days": age_days,
                            "description": f"Access key {key_id} is {age_days} days old (exceeds {max_key_age_days}d threshold)"
                        })

                    # Check last used date
                    try:
                        last_used_resp = iam.get_access_key_last_used(AccessKeyId=key_id)
                        last_used_info = last_used_resp.get("AccessKeyLastUsed", {})
                        last_used_date = last_used_info.get("LastUsedDate")

                        if last_used_date:
                            idle_days = (now - last_used_date).days
                            if idle_days > inactive_days_threshold:
                                report["inactive_keys_count"] += 1
                                user_findings.append({
                                    "type": "KEY_INACTIVE",
                                    "severity": "MEDIUM",
                                    "key_id": key_id,
                                    "idle_days": idle_days,
                                    "description": f"Access key {key_id} unused for {idle_days} days (threshold: {inactive_days_threshold}d)"
                                })
                        else:
                            # Never used and older than threshold
                            if age_days > inactive_days_threshold:
                                report["inactive_keys_count"] += 1
                                user_findings.append({
                                    "type": "KEY_NEVER_USED",
                                    "severity": "MEDIUM",
                                    "key_id": key_id,
                                    "description": f"Access key {key_id} created {age_days} days ago was NEVER used"
                                })
                    except ClientError:
                        pass

            except ClientError as e:
                user_findings.append({
                    "type": "ERROR",
                    "severity": "LOW",
                    "description": f"Failed to list keys: {str(e)}"
                })

            if user_findings:
                report["findings"].append({
                    "user": username,
                    "issues": user_findings
                })

    return report


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enterprise AWS DevSecOps: Audit IAM credentials, key ages, and MFA compliance."
    )
    parser.add_argument("--profile", default=None, help="AWS CLI profile")
    parser.add_argument("--max-key-age", type=int, default=90, help="Max allowed key age in days (default: 90)")
    parser.add_argument("--inactive-days", type=int, default=90, help="Threshold for inactive keys in days (default: 90)")
    parser.add_argument("--strict", action="store_true", help="Exit code 1 if any high-risk compliance findings exist")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    session = get_session(args.profile)

    if not args.json:
        print(f"\n{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD} 🔑 AWS IAM CREDENTIAL & CIS BENCHMARK AUDITOR{Colors.RESET}")
        print(f" Thresholds: Max Key Age: {args.max_key_age}d | Inactivity: {args.inactive_days}d")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    report = audit_iam(session, max_key_age_days=args.max_key_age, inactive_days_threshold=args.inactive_days)

    if not args.json:
        print(f"Scanned {report['users_scanned']} IAM users ({report['total_active_keys']} active keys).\n")

        if not report["findings"]:
            print(f"  {Colors.GREEN}✅ Perfect compliance! All keys rotated within {args.max_key_age} days and MFA enforced.{Colors.RESET}\n")
        else:
            for item in report["findings"]:
                print(f"{Colors.BOLD}👤 User: {Colors.CYAN}{item['user']}{Colors.RESET}")
                for issue in item["issues"]:
                    sev = issue["severity"]
                    color = Colors.RED if sev == "HIGH" else Colors.YELLOW
                    print(f"  • {color}[{sev}]{Colors.RESET} {issue['description']}")
                print()

        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f" Users Audited        : {report['users_scanned']}")
        print(f" Active Keys          : {report['total_active_keys']}")
        print(f" Aged Keys (> {args.max_key_age}d)    : {Colors.RED if report['aged_keys_count'] > 0 else Colors.GREEN}{report['aged_keys_count']}{Colors.RESET}")
        print(f" Inactive Keys (> {args.inactive_days}d): {Colors.YELLOW if report['inactive_keys_count'] > 0 else Colors.GREEN}{report['inactive_keys_count']}{Colors.RESET}")
        print(f" Console without MFA  : {Colors.RED if report['mfa_missing_count'] > 0 else Colors.GREEN}{report['mfa_missing_count']}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")
    else:
        print(json.dumps(report, indent=2))

    if args.strict and (report["aged_keys_count"] > 0 or report["mfa_missing_count"] > 0):
        print(f"{Colors.RED}❌ Strict check failed: Found aged keys or users without MFA.{Colors.RESET}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
