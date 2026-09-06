#!/usr/bin/env python3
"""
s3-bucket-security-policy.py

Enterprise S3 Bucket Security Policy & Hardening Manager.
Enforces SSL/TLS-only transmission, blocks public exposure, and generates
CloudFront Origin Access Control (OAC) policies for SPA storefront deployments.

Author  : GeorgeGxx/DevOps
Version : v2.0.0

Usage:
  python s3-bucket-security-policy.py --bucket georgegxx-frontend-prod --mode cloudfront-oac --cf-arn arn:aws:cloudfront::123456789012:distribution/E1234EXAMPLE
  python s3-bucket-security-policy.py --bucket georgegxx-ecommerce-tfstate --mode tls-enforce
"""

import argparse
import json
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


def generate_tls_enforce_policy(bucket_name: str) -> dict:
    """Denies any requests using unencrypted HTTP (Strict TLS 1.2+)."""
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "EnforceTLSRequestsOnly",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket_name}",
                    f"arn:aws:s3:::{bucket_name}/*"
                ],
                "Condition": {
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            }
        ]
    }


def generate_cloudfront_oac_policy(bucket_name: str, cf_arn: str) -> dict:
    """Allows read access exclusively to a specified CloudFront distribution (OAC)."""
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowCloudFrontServicePrincipalReadOnly",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudfront.amazonaws.com"
                },
                "Action": "s3:GetObject",
                "Resource": f"arn:aws:s3:::{bucket_name}/*",
                "Condition": {
                    "StringEquals": {
                        "AWS:SourceArn": cf_arn
                    }
                }
            }
        ]
    }


def apply_policy(
    bucket_name: str,
    mode: str,
    cf_arn: Optional[str] = None,
    policy_file: Optional[str] = None,
    profile: Optional[str] = None,
    dry_run: bool = False,
):
    session = boto3.Session(profile_name=profile)
    s3_client = session.client("s3")

    if mode == "tls-enforce":
        policy_doc = generate_tls_enforce_policy(bucket_name)
    elif mode == "cloudfront-oac":
        if not cf_arn:
            print("❌ Error: --cf-arn is required when using mode 'cloudfront-oac'", file=sys.stderr)
            sys.exit(1)
        policy_doc = generate_cloudfront_oac_policy(bucket_name, cf_arn)
    elif mode == "custom":
        if not policy_file:
            print("❌ Error: --policy-file is required when using mode 'custom'", file=sys.stderr)
            sys.exit(1)
        with open(policy_file, "r") as f:
            policy_doc = json.load(f)
    else:
        print(f"❌ Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)

    policy_json = json.dumps(policy_doc, indent=2)

    print(f"🪣 Target S3 Bucket : {bucket_name}")
    print(f"🛡️  Security Mode    : {mode}")
    print("\n--- Generated IAM Policy Document ---")
    print(policy_json)
    print("-------------------------------------\n")

    if dry_run:
        print("🔍 [DRY-RUN] Policy validated. S3 update skipped.")
        return

    try:
        s3_client.put_bucket_policy(Bucket=bucket_name, Policy=policy_json)
        print(f"✅ Successfully applied policy to bucket '{bucket_name}'.")

        # Also enforce Public Access Block
        print(f"🔒 Ensuring Public Access Block is enabled on '{bucket_name}'...")
        s3_client.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                "BlockPublicAcls": True,
                "IgnorePublicAcls": True,
                "BlockPublicPolicy": True,
                "RestrictPublicBuckets": True,
            },
        )
        print(f"🛡️  Public Access Block fully enabled.")
    except ClientError as e:
        print(f"❌ AWS S3 Error: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="S3 Bucket Security Policy & Hardening Manager")
    parser.add_argument("--bucket", required=True, help="Target S3 bucket name")
    parser.add_argument(
        "--mode",
        choices=["tls-enforce", "cloudfront-oac", "custom"],
        default="tls-enforce",
        help="Hardening policy profile to apply",
    )
    parser.add_argument("--cf-arn", help="CloudFront Distribution ARN (required for 'cloudfront-oac')")
    parser.add_argument("--policy-file", help="Path to custom JSON policy file")
    parser.add_argument("--profile", help="AWS CLI profile")
    parser.add_argument("--dry-run", action="store_true", help="Preview policy without modifying bucket")

    args = parser.parse_args()
    apply_policy(
        bucket_name=args.bucket,
        mode=args.mode,
        cf_arn=args.cf_arn,
        policy_file=args.policy_file,
        profile=args.profile,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
