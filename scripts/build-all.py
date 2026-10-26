#!/usr/bin/env python3
"""Builds Docker images for all microservices, frontend, and optional MLOps in the repository.

Usage:
    python scripts/build-all.py [tag] [--include-mlops] [--push]
    python scripts/build-all.py 1.0.0 --include-mlops --push
"""
import sys
import os
import time
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


def push_with_retry(image_name, max_retries=3, delay_seconds=5):
    """Pushes a container image with automatic exponential-style backoff retries.
    Handles transient network glitches, socket resets, and Docker Hub chunk timeouts
    ('error from registry: invalid content range').
    """
    cmd = ["docker", "push", image_name]
    for attempt in range(1, max_retries + 1):
        print(f"\n==> Pushing {image_name} (attempt {attempt}/{max_retries})...")
        result = subprocess.run(cmd)
        if result.returncode == 0:
            print(f"✅ Successfully pushed {image_name}")
            return True
        print(f"⚠️ Push attempt {attempt} failed with exit code {result.returncode}.")
        if attempt < max_retries:
            wait_time = delay_seconds * attempt
            print(f"⏳ Waiting {wait_time}s before retrying push for {image_name}...")
            time.sleep(wait_time)
    print(f"❌ Failed to push {image_name} after {max_retries} attempts.")
    sys.exit(1)


ALL_TARGETS = ["all"] + SERVICES + ["frontend"] + [ml["name"] for ml in MLOPS_SERVICES]


def main():
    parser = argparse.ArgumentParser(description="Build all microservice Docker images")
    parser.add_argument("tag", nargs="?", default="1.0.0", help="Image tag (default: 1.0.0)")
    parser.add_argument("--repo-prefix", default="georgegxx", help="Docker registry prefix")
    parser.add_argument("--service", choices=ALL_TARGETS, default="all", help="Target a specific service (default: all)")
    parser.add_argument("--exclude-service", action="append", choices=SERVICES, default=[], help="Skip building a microservice image (may be passed more than once)")
    parser.add_argument("--include-mlops", action="store_true", help="Also build MLOps images (forecast, training, mlflow)")
    parser.add_argument("--no-cache", action="store_true", help="Build Docker images without cache")
    parser.add_argument("--push", action="store_true", help="Push built images to Docker Registry after building")
    parser.add_argument("--push-only", action="store_true", help="Skip build step and only push existing images to registry")
    args = parser.parse_args()

    tag = args.tag
    prefix = args.repo_prefix
    target_svc = args.service
    built_images = []

    print("=" * 60)
    mode_msg = "PUSHING EXISTING" if args.push_only else "BUILDING"
    print(f" 🚀 {mode_msg} CONTAINER IMAGES ({prefix}/*:{tag}) [Target: {target_svc}]")
    print("=" * 60)

    # Determine services to process
    if target_svc == "all":
        services_to_build = [svc for svc in SERVICES if svc not in args.exclude_service]
        build_frontend = True
        mlops_to_build = MLOPS_SERVICES if args.include_mlops else []
    elif target_svc in SERVICES:
        services_to_build = [target_svc]
        build_frontend = False
        mlops_to_build = []
    elif target_svc == "frontend":
        services_to_build = []
        build_frontend = True
        mlops_to_build = []
    else:  # MLOps target
        services_to_build = []
        build_frontend = False
        mlops_to_build = [ml for ml in MLOPS_SERVICES if ml["name"] == target_svc]

    if not args.push_only:
        # 1. Build Spring Boot Microservices
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
        if build_frontend:
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

        # 3. Build MLOps Stack (Optional or targeted)
        for ml in mlops_to_build:
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
    else:
        for svc in services_to_build:
            built_images.append(f"{prefix}/{svc}:{tag}")
        if build_frontend:
            built_images.append(f"{prefix}/frontend:{tag}")
        for ml in mlops_to_build:
            built_images.append(f"{prefix}/{ml['name']}:{tag}")

    # 4. Optional Push
    if args.push or args.push_only:
        print("\n" + "=" * 60)
        print(" 📤 PUSHING IMAGES TO REGISTRY (WITH AUTOMATIC RETRIES)...")
        print("=" * 60)
        for img in built_images:
            push_with_retry(img, max_retries=3, delay_seconds=5)
        print("\n" + "=" * 60)
        print(" ✅ ALL REQUESTED IMAGES PUSHED SUCCESSFULLY!")
        print("=" * 60)


if __name__ == "__main__":
    main()

