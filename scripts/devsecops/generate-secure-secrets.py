#!/usr/bin/env python3
"""
generate-secure-secrets.py

Enterprise Zero-Trust Cryptographic Secret & Credential Generator.
Replaces insecure default credentials with high-entropy cryptographic strings (CSPRNG)
suitable for Kubernetes Secrets, HashiCorp Vault, Keycloak IAM, and PostgreSQL databases.

Author  : GeorgeGxx/DevOps
Version : v2.0.0

Usage:
  python generate-secure-secrets.py --format env
  python generate-secure-secrets.py --format k8s-yaml --output-file k8s/secrets.yaml
  python generate-secure-secrets.py --format json
"""

import argparse
import base64
import json
import secrets
import string
import sys
from typing import Dict

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def generate_alphanumeric_secret(length: int = 32) -> str:
    """Generates high-entropy alphanumeric credentials without problematic shell characters."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def generate_complex_password(length: int = 32) -> str:
    """Generates strong passwords containing symbols, uppercase, lowercase, and digits."""
    safe_symbols = "!@#$%^&*()-_=+"
    alphabet = string.ascii_letters + string.digits + safe_symbols
    # Guarantee at least one of each character category
    password = [
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.digits),
        secrets.choice(safe_symbols),
    ]
    password += [secrets.choice(alphabet) for _ in range(length - 4)]
    secrets.SystemRandom().shuffle(password)
    return "".join(password)


def generate_jwt_key(bits: int = 256) -> str:
    """Generates a secure 256-bit or 512-bit Base64-encoded HMAC key."""
    random_bytes = secrets.token_bytes(bits // 8)
    return base64.b64encode(random_bytes).decode("utf-8")


def build_credentials_bundle(length: int = 32) -> Dict[str, str]:
    """Builds a complete, unified credentials dictionary for all microservices."""
    return {
        "POSTGRES_PASSWORD_ORDERS": generate_complex_password(length),
        "POSTGRES_PASSWORD_PRODUCTS": generate_complex_password(length),
        "POSTGRES_PASSWORD_INVENTORY": generate_complex_password(length),
        "POSTGRES_PASSWORD_KEYCLOAK": generate_complex_password(length),
        "KEYCLOAK_ADMIN_PASSWORD": generate_complex_password(length),
        "KEYCLOAK_CLIENT_SECRET": generate_alphanumeric_secret(48),
        "REDIS_PASSWORD": generate_alphanumeric_secret(length),
        "KAFKA_SASL_PASSWORD": generate_alphanumeric_secret(length),
        "JWT_SECRET_KEY": generate_jwt_key(256),
    }


def format_as_env(creds: Dict[str, str]) -> str:
    lines = ["# Automated Zero-Trust Generated Credentials", "# Generated via scripts/devsecops/generate-secure-secrets.py", ""]
    for k, v in creds.items():
        lines.append(f'{k}="{v}"')
    return "\n".join(lines)


def format_as_k8s_secret(creds: Dict[str, str], name: str = "microservices-secrets", namespace: str = "staging") -> str:
    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        f"  name: {name}",
        f"  namespace: {namespace}",
        "type: Opaque",
        "stringData:",
    ]
    for k, v in creds.items():
        lines.append(f'  {k}: "{v}"')
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="🔐 Zero-Trust Cryptographic Secret & Credential Generator",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--format",
        choices=["env", "k8s-yaml", "json"],
        default="env",
        help="Output format: .env file, Kubernetes Secret manifest, or JSON (Default: env)",
    )
    parser.add_argument("--length", type=int, default=32, help="Minimum character length for generated passwords (Default: 32)")
    parser.add_argument("--output-file", help="Optional file path to write output directly")
    parser.add_argument("--namespace", default="staging", help="Target Kubernetes namespace when using format 'k8s-yaml' (Default: staging)")

    args = parser.parse_args()
    creds = build_credentials_bundle(length=args.length)

    if args.format == "env":
        output_content = format_as_env(creds)
    elif args.format == "k8s-yaml":
        output_content = format_as_k8s_secret(creds, namespace=args.namespace)
    elif args.format == "json":
        output_content = json.dumps(creds, indent=2)
    else:
        output_content = ""

    if args.output_file:
        with open(args.output_file, "w", encoding="utf-8") as f:
            f.write(output_content + "\n")
        print(f"✅ Generated secure secrets written to: {args.output_file}")
    else:
        print(output_content)


if __name__ == "__main__":
    main()
