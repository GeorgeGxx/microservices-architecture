#!/usr/bin/env python3
"""Builds Docker images for all microservices and the frontend in the repository.

Usage:
    python scripts/build-all.py [tag]
    python scripts/build-all.py 1.0.0
"""
import sys
import os
import subprocess
import argparse

if sys.platform == "win32":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

SERVICES = [
    "inventory-service",
    "notification-service",
    "orders-service",
    "products-service",
]


def run_command(cmd, cwd=None):
    print(f"\n==> Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        print(f"❌ Command failed with exit code {result.returncode}")
        sys.exit(result.returncode)


def main():
    parser = argparse.ArgumentParser(description="Build all microservice Docker images")
    parser.add_argument("tag", nargs="?", default="1.0.0", help="Image tag (default: 1.0.0)")
    parser.add_argument("--repo-prefix", default="georgegxx", help="Docker registry prefix")
    parser.add_argument("--no-cache", action="store_true", help="Build Docker images without cache")
    args = parser.parse_args()

    tag = args.tag
    prefix = args.repo_prefix

    print("=" * 60)
    print(f" 🚀 BUILDING ALL CONTAINER IMAGES ({prefix}/*:{tag})")
    print("=" * 60)

    # 1. Build Spring Boot Microservices
    for svc in SERVICES:
        image_name = f"{prefix}/{svc}:{tag}"
        print(f"\n📦 Building service '{image_name}'...")
        dockerfile = os.path.join(ROOT_DIR, svc, "Dockerfile")
        cmd = [
            "docker", "build",
            "-t", image_name,
            "-f", dockerfile,
            ROOT_DIR
        ]
        if args.no_cache:
            cmd.insert(2, "--no-cache")
        run_command(cmd, cwd=ROOT_DIR)

    # 2. Build Frontend SPA
    frontend_image = f"{prefix}/frontend:{tag}"
    print(f"\n🌐 Building frontend SPA '{frontend_image}'...")
    frontend_dir = os.path.join(ROOT_DIR, "frontend")
    frontend_dockerfile = os.path.join(frontend_dir, "Dockerfile")
    cmd = [
        "docker", "build",
        "-t", frontend_image,
        "-f", frontend_dockerfile,
        frontend_dir
    ]
    if args.no_cache:
        cmd.insert(2, "--no-cache")
    run_command(cmd, cwd=frontend_dir)

    print("\n" + "=" * 60)
    print(" ✨ ALL CONTAINER IMAGES BUILT SUCCESSFULLY!")
    print("=" * 60)


if __name__ == "__main__":
    main()
