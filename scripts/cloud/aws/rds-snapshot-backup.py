#!/usr/bin/env python3
"""
rds-snapshot-backup.py

Automated Disaster Recovery & Pre-deployment Snapshot Manager for Amazon RDS PostgreSQL.
Takes timestamped snapshots, assigns compliance tags, and optionally purges expired snapshots.

Author  : GeorgeGxx/DevOps
Version : v2.0.0

Usage:
  python rds-snapshot-backup.py --db-instance msa-aws-prod-postgres --environment prod
  python rds-snapshot-backup.py --db-instance ecommerce-db --retention-days 14 --wait
"""

import argparse
from datetime import datetime, timezone
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from typing import Optional

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
except ImportError:
    print("❌ Error: boto3 is not installed. Run: pip install boto3", file=sys.stderr)
    sys.exit(1)


def create_snapshot(
    db_instance: str,
    environment: str,
    region: str,
    profile: Optional[str] = None,
    wait: bool = False,
    retention_days: int = 30,
    dry_run: bool = False,
):
    session = boto3.Session(profile_name=profile, region_name=region)
    rds = session.client("rds")

    now = datetime.now(timezone.utc)
    timestamp_str = now.strftime("%Y%m%d-%H%M%S")
    snapshot_id = f"{db_instance}-{environment}-{timestamp_str}"

    print(f"📦 Target DB Instance : {db_instance}")
    print(f"🌍 AWS Region         : {region}")
    print(f"🏷️  Snapshot Identifier : {snapshot_id}")

    if dry_run:
        print("🔍 [DRY-RUN] Snapshot creation simulated. No AWS calls made.")
        return

    try:
        # Create Snapshot
        print(f"⚡ Initiating snapshot '{snapshot_id}'...")
        response = rds.create_db_snapshot(
            DBSnapshotIdentifier=snapshot_id,
            DBInstanceIdentifier=db_instance,
            Tags=[
                {"Key": "Environment", "Value": environment},
                {"Key": "ManagedBy", "Value": "DevSecOps-Automation"},
                {"Key": "CreatedAt", "Value": now.isoformat()},
            ],
        )
        print(f"✅ Snapshot '{snapshot_id}' requested successfully (Status: {response['DBSnapshot']['Status']}).")

        if wait:
            print("⏳ Waiting for snapshot to enter 'available' state (this may take a few minutes)...")
            waiter = rds.get_waiter("db_snapshot_available")
            waiter.wait(
                DBSnapshotIdentifier=snapshot_id,
                WaiterConfig={"Delay": 15, "MaxAttempts": 40},
            )
            print("🎉 Snapshot is now AVAILABLE and verified.")

        # Cleanup expired snapshots
        if retention_days > 0:
            purge_expired_snapshots(rds, db_instance, retention_days)

    except ClientError as e:
        print(f"❌ RDS Error: {e}", file=sys.stderr)
        sys.exit(1)


def purge_expired_snapshots(rds_client, db_instance: str, retention_days: int):
    """Purges snapshots older than the specified retention period."""
    print(f"\n🧹 Checking for snapshots older than {retention_days} days...")
    try:
        snapshots = rds_client.describe_db_snapshots(
            DBInstanceIdentifier=db_instance,
            SnapshotType="manual",
        ).get("DBSnapshots", [])

        now = datetime.now(timezone.utc)
        deleted = 0

        for snap in snapshots:
            create_time = snap.get("SnapshotCreateTime")
            if create_time:
                age_days = (now - create_time).days
                if age_days > retention_days:
                    snap_id = snap["DBSnapshotIdentifier"]
                    print(f"  🗑️  Deleting expired snapshot: {snap_id} ({age_days} days old)")
                    rds_client.delete_db_snapshot(DBSnapshotIdentifier=snap_id)
                    deleted += 1

        print(f"✨ Purge completed: {deleted} expired snapshots deleted.")
    except ClientError as e:
        print(f"⚠️  Retention purge warning: {e}")


def main():
    parser = argparse.ArgumentParser(description="Automated Disaster Recovery RDS Snapshot Manager")
    parser.add_argument("--db-instance", required=True, help="Target RDS DB Instance Identifier")
    parser.add_argument("--environment", default="prod", choices=["dev", "staging", "prod"], help="Environment tag")
    parser.add_argument("--region", default="us-east-1", help="AWS Region (Default: us-east-1)")
    parser.add_argument("--retention-days", type=int, default=30, help="Days to retain snapshots before purging (0 to disable)")
    parser.add_argument("--wait", action="store_true", help="Wait synchronously until snapshot becomes available")
    parser.add_argument("--dry-run", action="store_true", help="Simulate execution without creating AWS resources")
    parser.add_argument("--profile", help="AWS CLI profile name")

    args = parser.parse_args()
    create_snapshot(
        db_instance=args.db_instance,
        environment=args.environment,
        region=args.region,
        profile=args.profile,
        wait=args.wait,
        retention_days=args.retention_days,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
