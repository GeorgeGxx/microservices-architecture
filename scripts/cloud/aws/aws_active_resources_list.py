#!/usr/bin/env python3
"""
This script lists active resources in an AWS account using boto3.
Author : GeorgeGxx/DevOps
Version: v0.3.0 (Python / boto3 port)

Supported AWS services:
 1. EC2
 2. IAM     (global - queried once)
 3. S3      (global - queried once)
 4. VPC
 5. SNS
 6. EBS
 7. Route53 (global - queried once)
 8. Lambda
 9. SQS
 10. Glue
 11. CloudFormation
 12. KMS

Usage:
    python aws_active_resources_list.py <region|all> <service_name|all> [profile]
Examples:
    python aws_active_resources_list.py us-east-1 ec2
    python aws_active_resources_list.py all ec2
    python aws_active_resources_list.py all ec2 my-profile
    python aws_active_resources_list.py all all
    python aws_active_resources_list.py us-east-1 all
"""

import sys
import boto3
from botocore.exceptions import (
    ClientError,
    NoCredentialsError,
    EndpointConnectionError,
    ConnectTimeoutError,
    ProfileNotFound,
)

# Ensure UTF-8 output encoding across terminals (especially Windows cmd/pwsh cp1252)
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REGIONAL_SERVICES = [
    "ec2",
    "vpc",
    "lambda",
    "glue",
    "cloudformation",
    "kms",
    "sns",
    "sqs",
    "ebs",
]

GLOBAL_SERVICES = ["s3", "iam", "route53"]

# Allow both 'all' and legacy 'todos' for backward compatibility
ALL_VALID_SERVICES = set(REGIONAL_SERVICES + GLOBAL_SERVICES + ["all", "todos"])

SERVICE_ABBR = {
    "ec2": "EC2",
    "vpc": "VPC",
    "lambda": "LMB",
    "glue": "GLU",
    "cloudformation": "CFN",
    "kms": "KMS",
    "sns": "SNS",
    "sqs": "SQS",
    "ebs": "EBS",
}

# Global counters & trackers
ok_count = 0
fail_count = 0
skipped_count = 0
failed_regions = []
skipped_regions = []


def print_table(headers, rows):
    """Prints a formatted text table similar to AWS CLI --output table."""
    if not rows:
        return
    col_widths = [len(h) for h in headers]
    str_rows = []
    for r in rows:
        s_row = [str(x) if x is not None else "" for x in r]
        str_rows.append(s_row)
        for i, val in enumerate(s_row):
            if len(val) > col_widths[i]:
                col_widths[i] = len(val)

    sep = "+-" + "-+-".join("-" * w for w in col_widths) + "-+"
    print(sep)
    header_line = "| " + " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(headers)) + " |"
    print(header_line)
    print(sep)
    for r in str_rows:
        row_line = "| " + " | ".join(r[i].ljust(col_widths[i]) for i in range(len(headers))) + " |"
        print(row_line)
    print(sep)


def classify_error(err, region, label):
    """Classifies AWS ClientError/Exceptions and updates failure/skip counters."""
    global ok_count, fail_count, skipped_count
    err_str = str(err)
    error_code = ""
    if isinstance(err, ClientError):
        error_code = err.response.get("Error", {}).get("Code", "")

    if (
        "OptInRequired" in error_code
        or "not opted in" in err_str.lower()
        or "not subscribed" in err_str.lower()
        or error_code == "AuthFailure"
    ):
        print(f"  ⚠️  [{region}] {label}: region not enabled (opt-in required). Skipped.")
        skipped_count += 1
        skipped_regions.append(f"{region} ({label}) - opt-in required")
        return "opt"
    elif (
        "AccessDenied" in error_code
        or "UnauthorizedOperation" in error_code
        or "not authorized" in err_str.lower()
    ):
        print(f"  ❌ [{region}] {label}: insufficient permissions (AccessDenied).")
        fail_count += 1
        failed_regions.append(f"{region} ({label}) - AccessDenied")
        return "ERR"
    elif (
        isinstance(err, (EndpointConnectionError, ConnectTimeoutError))
        or "could not connect" in err_str.lower()
        or "timeout" in err_str.lower()
        or "connection" in err_str.lower()
        or "network" in err_str.lower()
    ):
        print(f"  ❌ [{region}] {label}: network error / timeout.")
        fail_count += 1
        failed_regions.append(f"{region} ({label}) - network error")
        return "ERR"
    else:
        first_line = err_str.splitlines()[0] if err_str else str(type(err).__name__)
        print(f"  ❌ [{region}] {label}: unexpected error -> {first_line}")
        fail_count += 1
        failed_regions.append(f"{region} ({label}) - unexpected error")
        return "ERR"


def get_session(profile=None):
    """Returns a boto3 Session for the given profile."""
    if profile:
        return boto3.Session(profile_name=profile)
    return boto3.Session()


def run_for_region(session, region, service):
    """Executes single-service resource query and detailed output for a region."""
    global ok_count
    try:
        if service == "ec2":
            print(f"== EC2 Instances - {region} ==")
            client = session.client("ec2", region_name=region)
            resp = client.describe_instances()
            rows = []
            for res in resp.get("Reservations", []):
                for inst in res.get("Instances", []):
                    rows.append([
                        inst.get("InstanceId"),
                        inst.get("State", {}).get("Name"),
                        inst.get("InstanceType"),
                    ])
            print_table(["InstanceId", "State", "InstanceType"], rows)
            ok_count += 1

        elif service == "vpc":
            print(f"== VPCs - {region} ==")
            client = session.client("ec2", region_name=region)
            resp = client.describe_vpcs()
            rows = [
                [v.get("VpcId"), v.get("CidrBlock"), v.get("IsDefault")]
                for v in resp.get("Vpcs", [])
            ]
            print_table(["VpcId", "CidrBlock", "IsDefault"], rows)
            ok_count += 1

        elif service == "lambda":
            print(f"== Lambda Functions - {region} ==")
            client = session.client("lambda", region_name=region)
            resp = client.list_functions()
            rows = [
                [f.get("FunctionName"), f.get("Runtime"), f.get("LastModified")]
                for f in resp.get("Functions", [])
            ]
            print_table(["FunctionName", "Runtime", "LastModified"], rows)
            ok_count += 1

        elif service == "glue":
            print(f"== Glue Jobs - {region} ==")
            client = session.client("glue", region_name=region)
            resp_jobs = client.get_jobs()
            rows_jobs = [
                [j.get("Name"), j.get("Role"), str(j.get("CreatedOn"))]
                for j in resp_jobs.get("Jobs", [])
            ]
            print_table(["Name", "Role", "CreatedOn"], rows_jobs)

            print(f"== Glue Crawlers - {region} ==")
            resp_crawlers = client.get_crawlers()
            rows_crawlers = [
                [c.get("Name"), c.get("State"), c.get("LastCrawl", {}).get("Status")]
                for c in resp_crawlers.get("Crawlers", [])
            ]
            print_table(["Name", "State", "LastCrawlStatus"], rows_crawlers)
            ok_count += 1

        elif service == "cloudformation":
            print(f"== CloudFormation Stacks - {region} ==")
            client = session.client("cloudformation", region_name=region)
            resp = client.list_stacks(
                StackStatusFilter=[
                    "CREATE_COMPLETE",
                    "UPDATE_COMPLETE",
                    "ROLLBACK_COMPLETE",
                    "UPDATE_ROLLBACK_COMPLETE",
                ]
            )
            rows = [
                [s.get("StackName"), s.get("StackStatus"), str(s.get("CreationTime"))]
                for s in resp.get("StackSummaries", [])
            ]
            print_table(["StackName", "StackStatus", "CreationTime"], rows)
            ok_count += 1

        elif service == "kms":
            print(f"== KMS Keys - {region} ==")
            client = session.client("kms", region_name=region)
            resp = client.list_keys()
            rows = [[k.get("KeyId")] for k in resp.get("Keys", [])]
            print_table(["KeyId"], rows)
            ok_count += 1

        elif service == "sns":
            print(f"== SNS Topics - {region} ==")
            client = session.client("sns", region_name=region)
            resp = client.list_topics()
            rows = [[t.get("TopicArn")] for t in resp.get("Topics", [])]
            print_table(["TopicArn"], rows)
            ok_count += 1

        elif service == "sqs":
            print(f"== SQS Queues - {region} ==")
            client = session.client("sqs", region_name=region)
            resp = client.list_queues()
            urls = resp.get("QueueUrls", []) or []
            rows = [[u] for u in urls]
            print_table(["QueueUrl"], rows)
            ok_count += 1

        elif service == "ebs":
            print(f"== EBS Volumes - {region} ==")
            client = session.client("ec2", region_name=region)
            resp = client.describe_volumes()
            rows = [
                [v.get("VolumeId"), v.get("Size"), v.get("State")]
                for v in resp.get("Volumes", [])
            ]
            print_table(["VolumeId", "Size", "State"], rows)
            ok_count += 1

    except Exception as e:
        classify_error(e, region, service.upper())


def run_global_service(session, service):
    """Executes queries for global AWS services."""
    global ok_count
    try:
        if service == "s3":
            print("== S3 Buckets (global) ==")
            client = session.client("s3")
            resp = client.list_buckets()
            rows = [
                [b.get("Name"), str(b.get("CreationDate"))]
                for b in resp.get("Buckets", [])
            ]
            print_table(["Name", "CreationDate"], rows)
            ok_count += 1

        elif service == "iam":
            print("== IAM Users (global) ==")
            client = session.client("iam")
            resp = client.list_users()
            rows = [
                [u.get("UserName"), str(u.get("CreateDate"))]
                for u in resp.get("Users", [])
            ]
            print_table(["UserName", "CreateDate"], rows)
            ok_count += 1

        elif service == "route53":
            print("== Route53 Hosted Zones (global) ==")
            client = session.client("route53")
            resp = client.list_hosted_zones()
            rows = [
                [z.get("Name"), z.get("Id")]
                for z in resp.get("HostedZones", [])
            ]
            print_table(["Name", "Id"], rows)
            ok_count += 1

    except Exception as e:
        classify_error(e, "global", service.upper())


def get_service_count(session, region, service):
    """Returns symbol for regional service count: '✓', '-', 'opt', or 'ERR'."""
    global ok_count
    try:
        count = 0
        if service == "ec2":
            client = session.client("ec2", region_name=region)
            resp = client.describe_instances()
            count = sum(len(r.get("Instances", [])) for r in resp.get("Reservations", []))
        elif service == "vpc":
            client = session.client("ec2", region_name=region)
            resp = client.describe_vpcs()
            count = len(resp.get("Vpcs", []))
        elif service == "lambda":
            client = session.client("lambda", region_name=region)
            resp = client.list_functions()
            count = len(resp.get("Functions", []))
        elif service == "cloudformation":
            client = session.client("cloudformation", region_name=region)
            resp = client.list_stacks(
                StackStatusFilter=[
                    "CREATE_COMPLETE",
                    "UPDATE_COMPLETE",
                    "ROLLBACK_COMPLETE",
                    "UPDATE_ROLLBACK_COMPLETE",
                ]
            )
            count = len(resp.get("StackSummaries", []))
        elif service == "kms":
            client = session.client("kms", region_name=region)
            resp = client.list_keys()
            count = len(resp.get("Keys", []))
        elif service == "sns":
            client = session.client("sns", region_name=region)
            resp = client.list_topics()
            count = len(resp.get("Topics", []))
        elif service == "sqs":
            client = session.client("sqs", region_name=region)
            resp = client.list_queues()
            count = len(resp.get("QueueUrls", []) or [])
        elif service == "ebs":
            client = session.client("ec2", region_name=region)
            resp = client.describe_volumes()
            count = len(resp.get("Volumes", []))
        elif service == "glue":
            client = session.client("glue", region_name=region)
            resp_jobs = client.get_jobs()
            resp_crawlers = client.get_crawlers()
            count = len(resp_jobs.get("Jobs", [])) + len(resp_crawlers.get("Crawlers", []))

        ok_count += 1
        return "✓" if count > 0 else "-"

    except Exception as e:
        return classify_error(e, region, service)


def get_global_count(session, service):
    """Returns symbol for global service count: '✓ (N)', '- (0)', or 'ERR'."""
    global ok_count, fail_count
    try:
        count = 0
        if service == "s3":
            client = session.client("s3")
            resp = client.list_buckets()
            count = len(resp.get("Buckets", []))
        elif service == "iam":
            client = session.client("iam")
            resp = client.list_users()
            count = len(resp.get("Users", []))
        elif service == "route53":
            client = session.client("route53")
            resp = client.list_hosted_zones()
            count = len(resp.get("HostedZones", []))

        ok_count += 1
        return f"✓ ({count})" if count > 0 else "- (0)"

    except Exception as e:
        fail_count += 1
        failed_regions.append(f"global ({service}) - error")
        return "ERR"


def run_all_services_matrix(session, aws_region):
    """Scans all regional and global services and prints matrix table."""
    if aws_region == "all":
        try:
            ec2_client = session.client("ec2")
            resp = ec2_client.describe_regions()
            regions_list = [r["RegionName"] for r in resp.get("Regions", [])]
        except Exception as e:
            print(f"Error fetching regions list: {e}")
            sys.exit(1)
    else:
        regions_list = [aws_region]

    matrix = {}
    print(
        f"Scanning {len(regions_list)} region(s) x {len(REGIONAL_SERVICES)} regional services... this may take a moment."
    )

    for region in regions_list:
        for service in REGIONAL_SERVICES:
            symbol = get_service_count(session, region, service)
            matrix[(region, service)] = symbol

    print("")
    header = f"{'Region':<16}" + "".join(
        f"{SERVICE_ABBR[service]:<6}" for service in REGIONAL_SERVICES
    )
    print(header)
    print("-" * 70)

    for region in regions_list:
        row = f"{region:<16}" + "".join(
            f"{matrix[(region, service)]:<6}" for service in REGIONAL_SERVICES
        )
        print(row)

    print("")
    print(
        "Legend: ✓ = resources found | - = empty | opt = region not enabled (opt-in) | ERR = error/permissions"
    )

    print("")
    print("-- Global Services --")
    for service in GLOBAL_SERVICES:
        res = get_global_count(session, service)
        print(f"{service.upper():<16} {res}")

    print_summary()


def print_summary():
    """Prints final summary of scans."""
    print("")
    print("==================== SUMMARY ====================")
    print(f"OK:       {ok_count}")
    print(f"Failed:   {fail_count}")
    print(f"Skipped:  {skipped_count}")

    if failed_regions:
        print("")
        print("-- Failures --")
        for item in failed_regions:
            print(f"  - {item}")

    if skipped_regions:
        print("")
        print("-- Skipped (Opt-in required) --")
        for item in skipped_regions:
            print(f"  - {item}")

    print("=================================================")


def main():
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print("Usage: python aws_active_resources_list.py <region|all> <service_name|all> [profile]")
        print("Example: python aws_active_resources_list.py all ec2")
        print("Example: python aws_active_resources_list.py us-east-1 all")
        sys.exit(1)

    aws_region = sys.argv[1].lower()
    aws_service = sys.argv[2].lower()
    aws_profile = sys.argv[3] if len(sys.argv) == 4 else None

    if aws_service not in ALL_VALID_SERVICES:
        print("Invalid service. Please enter a valid AWS service name or 'all'.")
        sys.exit(1)

    # Initialize boto3 Session
    try:
        session = get_session(aws_profile)
    except ProfileNotFound:
        print(f"AWS profile '{aws_profile}' was not found in AWS configuration.")
        sys.exit(1)

    # Validate authentication with STS
    try:
        sts_client = session.client("sts")
        sts_client.get_caller_identity()
    except (NoCredentialsError, ClientError, Exception):
        print("Could not authenticate with AWS. Please check your credentials/profile (expired or invalid).")
        sys.exit(1)

    # Dispatch logic
    if aws_service in ("all", "todos"):
        run_all_services_matrix(session, aws_region)
        sys.exit(1 if fail_count > 0 else 0)

    if aws_service in GLOBAL_SERVICES:
        run_global_service(session, aws_service)
        print_summary()
        sys.exit(1 if fail_count > 0 else 0)

    if aws_region == "all":
        try:
            ec2_client = session.client("ec2")
            regions = [r["RegionName"] for r in ec2_client.describe_regions().get("Regions", [])]
        except Exception as e:
            print(f"Error listing regions: {e}")
            sys.exit(1)

        for region in regions:
            run_for_region(session, region, aws_service)
    else:
        run_for_region(session, aws_region, aws_service)

    print_summary()
    sys.exit(1 if fail_count > 0 else 0)


if __name__ == "__main__":
    main()
