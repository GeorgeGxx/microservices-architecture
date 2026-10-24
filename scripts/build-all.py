#!/usr/bin/env python3
"""Builds Docker images for all microservices, frontend, and optional MLOps in the repository.

Usage:
    python scripts/build-all.py [tag] [--include-mlops] [--push]
    python scripts/build-all.py 1.0.0 --include-mlops --push
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

MLOPS_SERVICES = [
    {"name": "demand-forecast", "dockerfile": "mlops/Dockerfile.forecast", "context": "mlops"},
    {"name": "mlops-training", "dockerfile": "mlops/Dockerfile.training", "context": "mlops"},
    {"name": "mlflow", "dockerfile": "mlops/Dockerfile", "context": "mlops"},
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
    parser.add_argument("--exclude-service", action="append", choices=SERVICES, default=[], help="Skip building a microservice image (may be passed more than once)")
    parser.add_argument("--include-mlops", action="store_true", help="Also build MLOps images (forecast, training, mlflow)")
    parser.add_argument("--no-cache", action="store_true", help="Build Docker images without cache")
    parser.add_argument("--push", action="store_true", help="Push built images to Docker Registry after building")
    args = parser.parse_args()

    tag = args.tag
    prefix = args.repo_prefix
    built_images = []

    print("=" * 60)
    print(f" 🚀 BUILDING CONTAINER IMAGES ({prefix}/*:{tag})")
    print("=" * 60)

    # 1. Build Spring Boot Microservices
    services_to_build = [svc for svc in SERVICES if svc not in args.exclude_service]
    for svc in services_to_build:
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
        built_images.append(image_name)

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
    built_images.append(frontend_image)

    # 3. Build MLOps Stack (Optional)
    if args.include_mlops:
        print("\n📈 Building MLOps container images...")
        for ml in MLOPS_SERVICES:
            ml_image = f"{prefix}/{ml['name']}:{tag}"
            print(f"\n🧪 Building MLOps '{ml_image}'...")
            ml_context = os.path.join(ROOT_DIR, ml["context"])
            ml_dockerfile = os.path.join(ROOT_DIR, ml["dockerfile"])
            cmd = [
                "docker", "build",
                "-t", ml_image,
                "-f", ml_dockerfile,
                ml_context
            ]
            if args.no_cache:
                cmd.insert(2, "--no-cache")
            run_command(cmd, cwd=ml_context)
            built_images.append(ml_image)

    print("\n" + "=" * 60)
    print(" ✨ REQUESTED CONTAINER IMAGES BUILT SUCCESSFULLY!")
    print("=" * 60)

    # 4. Optional Push
    if args.push:
        print("\n" + "=" * 60)
        print(" 📤 PUSHING IMAGES TO REGISTRY...")
        print("=" * 60)
        for img in built_images:
            print(f"\nPushing {img}...")
            run_command(["docker", "push", img])
        print("\n" + "=" * 60)
        print(" ✅ ALL IMAGES PUSHED SUCCESSFULLY!")
        print("=" * 60)


if __name__ == "__main__":
    main()
