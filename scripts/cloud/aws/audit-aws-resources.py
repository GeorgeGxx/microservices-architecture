#!/usr/bin/env python3
"""
audit-aws-resources.py

Enterprise AWS Resource Inventory & FinOps Auditor.
Discovers active cloud resources across AWS regions, with specialized support
for Kubernetes microservices infrastructure (EKS, ECR, RDS, ALB/ELBv2, VPC, EBS).

Author  : GeorgeGxx/DevOps
Version : v2.0.0 (Enterprise Microservices Edition)

Usage:
  python audit-aws-resources.py --region us-east-1 --service all-services
  python audit-aws-resources.py --region all --service eks
  python audit-aws-resources.py --region us-east-1 --service rds --json
"""

import argparse
import json
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from typing import Any, Dict, List, Optional

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError, ProfileNotFound
except ImportError:
    print("❌ Error: boto3 is not installed. Run: pip install boto3", file=sys.stderr)
    sys.exit(1)

# ANSI Colors
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

REGIONAL_SERVICES = [
    "eks", "ecr", "rds", "elbv2", "vpc", "ebs", "ec2", "lambda", "kms", "sns", "sqs", "cloudformation"
]
GLOBAL_SERVICES = ["s3", "iam", "route53"]
ALL_SERVICES = REGIONAL_SERVICES + GLOBAL_SERVICES + ["all-services"]


def get_session(profile: Optional[str] = None) -> boto3.Session:
    """Initializes and returns a boto3 session with credential validation."""
    try:
        session = boto3.Session(profile_name=profile)
        # Test credentials
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


# --- Service Auditors ---

def audit_eks(session: boto3.Session, region: str) -> List[Dict[str, Any]]:
    client = session.client("eks", region_name=region)
    clusters = client.list_clusters().get("clusters", [])
    results = []
    for name in clusters:
        try:
            desc = client.describe_cluster(name=name)["cluster"]
            results.append({
                "Id": name,
                "Status": desc.get("status"),
                "Version": desc.get("version"),
                "Endpoint": desc.get("endpoint"),
            })
        except ClientError:
            results.append({"Id": name, "Status": "UNKNOWN"})
    return results


def audit_ecr(session: boto3.Session, region: str) -> List[Dict[str, Any]]:
    client = session.client("ecr", region_name=region)
    repos = client.describe_repositories().get("repositories", [])
    return [{"Id": r["repositoryName"], "Uri": r["repositoryUri"]} for r in repos]


def audit_rds(session: boto3.Session, region: str) -> List[Dict[str, Any]]:
    client = session.client("rds", region_name=region)
    dbs = client.describe_db_instances().get("DBInstances", [])
    return [{
        "Id": db["DBInstanceIdentifier"],
        "Engine": db["Engine"],
        "Class": db["DBInstanceClass"],
        "Status": db["DBInstanceStatus"],
        "MultiAZ": db["MultiAZ"],
    } for db in dbs]


def audit_elbv2(session: boto3.Session, region: str) -> List[Dict[str, Any]]:
    client = session.client("elbv2", region_name=region)
    albs = client.describe_load_balancers().get("LoadBalancers", [])
    return [{
        "Id": lb["LoadBalancerName"],
        "Type": lb["Type"],
        "Scheme": lb["Scheme"],
        "DNS": lb["DNSName"],
        "State": lb["State"]["Code"],
    } for lb in albs]


def audit_vpc(session: boto3.Session, region: str) -> List[Dict[str, Any]]:
    client = session.client("ec2", region_name=region)
    vpcs = client.describe_vpcs().get("Vpcs", [])
    return [{
        "Id": v["VpcId"],
        "CIDR": v["CidrBlock"],
        "IsDefault": v["IsDefault"],
    } for v in vpcs if not v["IsDefault"]]


def audit_ebs(session: boto3.Session, region: str) -> List[Dict[str, Any]]:
    client = session.client("ec2", region_name=region)
    vols = client.describe_volumes().get("Volumes", [])
    return [{
        "Id": v["VolumeId"],
        "SizeGB": v["Size"],
        "Type": v["VolumeType"],
        "State": v["State"],
        "Attached": len(v.get("Attachments", [])) > 0,
    } for v in vols]


def audit_s3(session: boto3.Session) -> List[Dict[str, Any]]:
    client = session.client("s3")
    buckets = client.list_buckets().get("Buckets", [])
    return [{"Id": b["Name"], "CreatedAt": str(b["CreationDate"])} for b in buckets]


def audit_iam(session: boto3.Session) -> List[Dict[str, Any]]:
    client = session.client("iam")
    roles = client.list_roles().get("Roles", [])
    # Filter out AWS service-linked roles for cleaner output
    custom_roles = [r for r in roles if not r["Path"].startswith("/aws-service-role/")]
    return [{"Id": r["RoleName"], "Arn": r["Arn"]} for r in custom_roles[:25]]


AUDIT_DISPATCH = {
    "eks": audit_eks,
    "ecr": audit_ecr,
    "rds": audit_rds,
    "elbv2": audit_elbv2,
    "vpc": audit_vpc,
    "ebs": audit_ebs,
}


def main():
    parser = argparse.ArgumentParser(
        description="🔍 Enterprise AWS Resource & FinOps Auditor",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--region", default="us-east-1", help="Target region or 'all' for multi-region sweep (Default: us-east-1)")
    parser.add_argument("--service", default="all-services", choices=ALL_SERVICES, help="Target service to audit (Default: all-services)")
    parser.add_argument("--profile", help="AWS CLI profile to use")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")

    args = parser.parse_args()
    session = get_session(args.profile)

    target_regions = get_available_regions(session) if args.region == "all" else [args.region]
    target_services = REGIONAL_SERVICES if args.service == "all-services" else [args.service]

    report: Dict[str, Any] = {"regions": {}}

    if not args.json:
        print(f"\n{Colors.BOLD}{Colors.HEADER}================================================================={Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.CYAN} ☁️  AWS ENTERPRISE AUDITOR & FINOPS INVENTORY REPORT{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.HEADER}================================================================={Colors.RESET}")
        print(f"Regions  : {', '.join(target_regions[:4])}{' (+' + str(len(target_regions)-4) + ' more)' if len(target_regions) > 4 else ''}")
        print(f"Services : {', '.join(target_services)}")
        print("-----------------------------------------------------------------\n")

    total_resources = 0

    for r in target_regions:
        report["regions"][r] = {}
        for s in target_services:
            if s in AUDIT_DISPATCH:
                try:
                    items = AUDIT_DISPATCH[s](session, r)
                    report["regions"][r][s] = items
                    count = len(items)
                    total_resources += count
                    if not args.json:
                        status_color = Colors.GREEN if count > 0 else Colors.DIM
                        icon = "📦" if count > 0 else "▫️ "
                        print(f" {icon} [{r:12}] {s.upper():<8} : {status_color}{count:2} active{Colors.RESET}")
                        if count > 0 and args.service != "all-services":
                            for item in items:
                                print(f"      ↳ {Colors.YELLOW}{item.get('Id')}{Colors.RESET} ({item})")
                except ClientError as e:
                    report["regions"][r][s] = {"error": str(e)}
                    if not args.json:
                        print(f" ⚠️  [{r:12}] {s.upper():<8} : {Colors.RED}Access Denied / Not Available{Colors.RESET}")

    # Global services
    if args.service in ["s3", "all-services"]:
        s3_items = audit_s3(session)
        report["s3"] = s3_items
        total_resources += len(s3_items)
        if not args.json:
            print(f" 🪣 [GLOBAL      ] S3       : {Colors.GREEN}{len(s3_items):2} buckets{Colors.RESET}")

    if args.service in ["iam", "all-services"]:
        iam_items = audit_iam(session)
        report["iam"] = iam_items
        total_resources += len(iam_items)
        if not args.json:
            print(f" 🔐 [GLOBAL      ] IAM      : {Colors.GREEN}{len(iam_items):2} custom roles{Colors.RESET}")

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("\n-----------------------------------------------------------------")
        print(f"{Colors.BOLD}Total Active Tracked Resources: {Colors.GREEN}{total_resources}{Colors.RESET}\n")


if __name__ == "__main__":
    main()
