#!/usr/bin/env python3
"""
check-security-groups.py

Enterprise AWS DevSecOps Security Group & Exposed Port Inspector.
Audits EC2/VPC/EKS Security Groups across regions to detect overly permissive ingress rules,
specifically targeting 0.0.0.0/0 and ::/0 access to sensitive ports (SSH, RDP, DBs, KubeAPI).

Author  : GeorgeGxx/DevOps
Version : v2.0.0 (Enterprise Microservices Edition)

Usage:
  # Scan primary region with formatted terminal report:
  python scripts/cloud/aws/check-security-groups.py --region us-east-1

  # Multi-region compliance scan:
  python scripts/cloud/aws/check-security-groups.py --region all

  # Fail pipeline (exit 1) if CRITICAL violations exist:
  python scripts/cloud/aws/check-security-groups.py --region us-east-1 --strict --json
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


# Sensitive ports map with severity classification
SENSITIVE_PORTS = {
    22: ("SSH (Remote Shell)", "CRITICAL"),
    3389: ("RDP (Windows Remote Desktop)", "CRITICAL"),
    5432: ("PostgreSQL Database", "CRITICAL"),
    3306: ("MySQL / MariaDB Database", "CRITICAL"),
    6379: ("Redis Cache / Store", "CRITICAL"),
    27017: ("MongoDB Database", "CRITICAL"),
    9092: ("Apache Kafka Broker", "HIGH"),
    6443: ("Kubernetes API Server", "HIGH"),
    9200: ("Elasticsearch REST API", "HIGH"),
    2379: ("etcd Client Port", "CRITICAL"),
    2380: ("etcd Peer Port", "CRITICAL"),
    8080: ("Alternate HTTP / App Proxy", "MEDIUM"),
}


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


def port_overlaps(from_port: Optional[int], to_port: Optional[int], target_port: int) -> bool:
    """Checks if a target port falls inside an ingress rule port range."""
    if from_port is None or to_port is None:
        return True  # All ports open (-1)
    return from_port <= target_port <= to_port


def audit_security_groups_in_region(session: boto3.Session, region: str) -> Dict[str, Any]:
    """Audits security groups in a given AWS region for public 0.0.0.0/0 exposure."""
    ec2 = session.client("ec2", region_name=region)
    result: Dict[str, Any] = {
        "region": region,
        "total_security_groups": 0,
        "violations": [],
        "critical_count": 0,
        "high_count": 0,
        "medium_count": 0
    }

    try:
        sgs = ec2.describe_security_groups().get("SecurityGroups", [])
        result["total_security_groups"] = len(sgs)

        for sg in sgs:
            sg_id = sg["GroupId"]
            sg_name = sg["GroupName"]
            vpc_id = sg.get("VpcId", "N/A")

            for perm in sg.get("IpPermissions", []):
                ip_protocol = perm.get("IpProtocol", "-1")
                from_port = perm.get("FromPort")
                to_port = perm.get("ToPort")

                # Check for public CIDR ranges
                ip_ranges = [r.get("CidrIp") for r in perm.get("IpRanges", [])]
                ipv6_ranges = [r.get("CidrIpv6") for r in perm.get("Ipv6Ranges", [])]
                is_public = ("0.0.0.0/0" in ip_ranges) or ("::/0" in ipv6_ranges)

                if not is_public:
                    continue

                # If all traffic is allowed (-1)
                if ip_protocol == "-1":
                    violation = {
                        "sg_id": sg_id,
                        "sg_name": sg_name,
                        "vpc_id": vpc_id,
                        "severity": "CRITICAL",
                        "issue": "All protocols and ports are open to the world (0.0.0.0/0)",
                        "protocol": "ALL",
                        "ports": "ALL"
                    }
                    result["violations"].append(violation)
                    result["critical_count"] += 1
                    continue

                # Check sensitive ports
                matched_ports = []
                max_severity = "LOW"
                for port, (desc, sev) in SENSITIVE_PORTS.items():
                    if port_overlaps(from_port, to_port, port):
                        matched_ports.append(f"{port} ({desc})")
                        if sev == "CRITICAL":
                            max_severity = "CRITICAL"
                        elif sev == "HIGH" and max_severity != "CRITICAL":
                            max_severity = "HIGH"
                        elif sev == "MEDIUM" and max_severity not in ("CRITICAL", "HIGH"):
                            max_severity = "MEDIUM"

                if matched_ports:
                    violation = {
                        "sg_id": sg_id,
                        "sg_name": sg_name,
                        "vpc_id": vpc_id,
                        "severity": max_severity,
                        "issue": f"Exposed sensitive ports: {', '.join(matched_ports)} to 0.0.0.0/0",
                        "protocol": ip_protocol,
                        "port_range": f"{from_port}-{to_port}" if from_port != to_port else str(from_port)
                    }
                    result["violations"].append(violation)
                    if max_severity == "CRITICAL":
                        result["critical_count"] += 1
                    elif max_severity == "HIGH":
                        result["high_count"] += 1
                    elif max_severity == "MEDIUM":
                        result["medium_count"] += 1

    except ClientError as e:
        result["error"] = str(e)

    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enterprise AWS DevSecOps: Audit Security Groups for 0.0.0.0/0 ingress exposure."
    )
    parser.add_argument("--region", default="us-east-1", help="Target AWS region or 'all'")
    parser.add_argument("--profile", default=None, help="AWS CLI profile")
    parser.add_argument("--strict", action="store_true", help="Exit code 1 if any CRITICAL or HIGH violations exist")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    session = get_session(args.profile)
    regions = get_available_regions(session) if args.region.lower() == "all" else [args.region]

    if not args.json:
        print(f"\n{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f"{Colors.BOLD} 🛡️ AWS SECURITY GROUP & INGRESS COMPLIANCE INSPECTOR{Colors.RESET}")
        print(f" CIS Benchmark Audit | Regions: {', '.join(regions)}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    all_results: List[Dict[str, Any]] = []
    total_sgs = 0
    total_critical = 0
    total_high = 0
    total_medium = 0

    for r in regions:
        res = audit_security_groups_in_region(session, r)
        all_results.append(res)
        total_sgs += res["total_security_groups"]
        total_critical += res["critical_count"]
        total_high += res["high_count"]
        total_medium += res["medium_count"]

        if not args.json:
            print(f"{Colors.BOLD}🌍 Region: {r} (Scanned {res['total_security_groups']} SGs){Colors.RESET}")
            if not res["violations"]:
                print(f"  {Colors.GREEN}✅ No public 0.0.0.0/0 ingress vulnerabilities detected.{Colors.RESET}\n")
                continue

            for v in res["violations"]:
                sev = v["severity"]
                if sev == "CRITICAL":
                    sev_color = f"{Colors.RED}{Colors.BOLD}[CRITICAL]{Colors.RESET}"
                elif sev == "HIGH":
                    sev_color = f"{Colors.YELLOW}{Colors.BOLD}[HIGH]{Colors.RESET}"
                else:
                    sev_color = f"{Colors.BLUE}[MEDIUM]{Colors.RESET}"

                print(f"  • {sev_color} SG: {Colors.CYAN}{v['sg_id']}{Colors.RESET} ({v['sg_name']}) in VPC {v['vpc_id']}")
                print(f"    Issue: {v['issue']}")

            print()

    if args.json:
        print(json.dumps({
            "results": all_results,
            "summary": {
                "total_security_groups": total_sgs,
                "critical": total_critical,
                "high": total_high,
                "medium": total_medium
            }
        }, indent=2))
    else:
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}")
        print(f" Total SGs Analyzed : {total_sgs}")
        print(f" 🔴 Critical Issues  : {total_critical}")
        print(f" 🟡 High Issues      : {total_high}")
        print(f" 🔵 Medium Issues    : {total_medium}")
        print(f"{Colors.BOLD}{Colors.CYAN}═══════════════════════════════════════════════════════════════{Colors.RESET}\n")

    if args.strict and (total_critical > 0 or total_high > 0):
        print(f"{Colors.RED}❌ Compliance check failed: Found {total_critical} critical and {total_high} high risk SG violations.{Colors.RESET}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
