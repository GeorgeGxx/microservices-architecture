#!/usr/bin/env python3
"""
s3-state-dr-sync.py

Disaster Recovery & Cross-Region S3 Synchronization Utility.
Safely replicates Terraform .tfstate archives, secrets, or frontend builds
between S3 buckets across AWS accounts or regions.

Author  : GeorgeGxx/DevOps
Version : v2.0.0

Usage:
  python s3-state-dr-sync.py --source georgegxx-ecommerce-tfstate --dest georgegxx-ecommerce-tfstate-dr-uswest2 --dest-region us-west-2
  python s3-state-dr-sync.py --source my-frontend-bucket --dest my-backup-bucket --dry-run
"""

import argparse
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from typing import Optional

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    print("❌ Error: boto3 is not installed. Run: pip install boto3", file=sys.stderr)
    sys.exit(1)


def sync_s3_buckets(
    source_bucket: str,
    dest_bucket: str,
    prefix: str = "",
    dest_region: Optional[str] = None,
    profile: Optional[str] = None,
    dry_run: bool = False,
):
    session = boto3.Session(profile_name=profile)
    s3_resource = session.resource("s3")
    s3_client = session.client("s3")

    print(f"📦 Source Bucket : s3://{source_bucket}/{prefix}")
    print(f"🎯 Dest Bucket   : s3://{dest_bucket}/{prefix}")
    if dest_region:
        print(f"🌍 Dest Region   : {dest_region}")

    try:
        # Verify source bucket access
        s3_client.head_bucket(Bucket=source_bucket)
    except ClientError as e:
        print(f"❌ Error: Cannot access source bucket '{source_bucket}': {e}", file=sys.stderr)
        sys.exit(1)

    try:
        # Verify destination bucket access
        s3_client.head_bucket(Bucket=dest_bucket)
    except ClientError:
        print(f"⚠️  Destination bucket '{dest_bucket}' not found. Attempting to create it...")
        if not dry_run:
            try:
                if dest_region and dest_region != "us-east-1":
                    s3_client.create_bucket(
                        Bucket=dest_bucket,
                        CreateBucketConfiguration={"LocationConstraint": dest_region},
                    )
                else:
                    s3_client.create_bucket(Bucket=dest_bucket)
                print(f"✅ Bucket '{dest_bucket}' created.")
            except ClientError as e:
                print(f"❌ Failed to create bucket: {e}", file=sys.stderr)
                sys.exit(1)

    src_b = s3_resource.Bucket(source_bucket)
    objects = list(src_b.objects.filter(Prefix=prefix))

    print(f"🔍 Discovered {len(objects)} object(s) to synchronize.")

    copied_count = 0
    total_bytes = 0

    for obj in objects:
        key = obj.key
        size = obj.size
        copy_source = {"Bucket": source_bucket, "Key": key}

        if dry_run:
            print(f"  [DRY-RUN] Would sync: {key} ({size:,} bytes)")
        else:
            try:
                dest_obj = s3_resource.Object(dest_bucket, key)
                dest_obj.copy(copy_source)
                print(f"  ✓ Synced: {key} ({size:,} bytes)")
                copied_count += 1
                total_bytes += size
            except ClientError as e:
                print(f"  ❌ Error copying '{key}': {e}", file=sys.stderr)

    if not dry_run:
        print(f"\n🎉 Synchronization complete: {copied_count} files synced ({total_bytes / (1024*1024):.2f} MB).")
    else:
        print("\n🔍 [DRY-RUN] Simulation finished. No data transferred.")


def main():
    parser = argparse.ArgumentParser(description="Cross-Region S3 Disaster Recovery & Sync Tool")
    parser.add_argument("--source", required=True, help="Source S3 bucket name")
    parser.add_argument("--dest", required=True, help="Destination S3 bucket name")
    parser.add_argument("--prefix", default="", help="Optional key prefix to filter objects")
    parser.add_argument("--dest-region", default="us-west-2", help="Destination AWS region (Default: us-west-2)")
    parser.add_argument("--profile", help="AWS CLI profile")
    parser.add_argument("--dry-run", action="store_true", help="Simulate replication without copying data")

    args = parser.parse_args()
    sync_s3_buckets(
        source_bucket=args.source,
        dest_bucket=args.dest,
        prefix=args.prefix,
        dest_region=args.dest_region,
        profile=args.profile,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
