#!/usr/bin/env python3
"""Select service CI jobs and Docker images from a Git change set."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import PurePosixPath

RELEASE_SERVICES = (
    "products-service",
    "orders-service",
    "inventory-service",
    "notification-service",
    "payments-service",
    "fulfillment-service",
    "analytics-service",
    "frontend",
    "ai-service",
    "demand-forecast",
    "mlops-training",
    "mlflow",
)

SPRING_SERVICES = (
    "products-service",
    "orders-service",
    "inventory-service",
    "notification-service",
)

CI_SERVICES = RELEASE_SERVICES + ("cosmo-router",)

SERVICE_WORKFLOW = {
    "products-service": {"service-type": "spring-boot", "service-dir": "products-service"},
    "orders-service": {"service-type": "spring-boot", "service-dir": "orders-service"},
    "inventory-service": {"service-type": "spring-boot", "service-dir": "inventory-service"},
    "notification-service": {"service-type": "spring-boot", "service-dir": "notification-service"},
    "payments-service": {
        "service-type": "go", "service-dir": "payments-service",
        "context-dir": "payments-service", "dockerfile-path": "payments-service/Dockerfile",
    },
    "fulfillment-service": {
        "service-type": "nestjs", "service-dir": "fulfillment-service",
        "context-dir": "fulfillment-service", "dockerfile-path": "fulfillment-service/Dockerfile",
    },
    "analytics-service": {
        "service-type": "python", "service-dir": "analytics-service",
        "context-dir": "analytics-service", "dockerfile-path": "analytics-service/Dockerfile",
    },
    "frontend": {"service-type": "react", "service-dir": "frontend"},
    "ai-service": {
        "service-type": "python", "service-dir": "ai-service",
        "context-dir": "ai-service", "dockerfile-path": "ai-service/Dockerfile",
    },
    "demand-forecast": {
        "service-type": "python", "service-dir": "mlops", "context-dir": "mlops",
        "dockerfile-path": "mlops/Dockerfile.forecast", "helm-values-key": "mlops.forecast",
    },
    "mlops-training": {
        "service-type": "python", "service-dir": "mlops", "context-dir": "mlops",
        "dockerfile-path": "mlops/Dockerfile.training", "helm-values-key": "mlops.training",
    },
    "mlflow": {
        "service-type": "python", "service-dir": "mlops", "context-dir": "mlops",
        "dockerfile-path": "mlops/Dockerfile", "helm-values-key": "mlops.mlflow",
    },
    "cosmo-router": {"service-type": "cosmo-router", "service-dir": "cosmo-router"},
}

_MLOPS_FORECAST = (
    "mlops/forecast_api.py", "mlops/Dockerfile.forecast", "mlops/tests/test_forecast_api.py",
)
_MLOPS_TRAINING = (
    "mlops/train_demand_model.py", "mlops/capture_orders.py", "mlops/container_train.sh",
    "mlops/Dockerfile.training", "mlops/requirements.container.txt", "mlops/patch_spark_jars.py",
    "mlops/tests/test_train_demand_model.py", "mlops/tests/test_capture_orders.py",
)
_MLOPS_SHARED = (
    "mlops/data_contracts.py", "mlops/feature_engineering.py", "mlops/model_invariants.py",
    "mlops/requirements.txt", "mlops/tests/test_data_contracts.py",
    "mlops/tests/test_feature_engineering.py", "mlops/tests/test_model_invariants.py",
)


def _add(selected: set[str], service: str) -> None:
    selected.add(service)


def _mlops_services(path: str) -> set[str]:
    if path in _MLOPS_FORECAST:
        return {"demand-forecast"}
    if path in _MLOPS_TRAINING:
        return {"mlops-training"}
    if path in _MLOPS_SHARED:
        return {"demand-forecast", "mlops-training"}
    if path == "mlops/Dockerfile":
        return {"mlflow"}
    return {"demand-forecast", "mlops-training", "mlflow"}


def affected_services(paths: list[str]) -> list[str]:
    """Return CI workloads affected by paths, in stable execution order."""
    selected: set[str] = set()
    for raw_path in paths:
        path = str(PurePosixPath(raw_path))
        first = path.split("/", 1)[0]
        if first in RELEASE_SERVICES and "/" in path:
            _add(selected, first)
        elif first == "mlops":
            selected.update(_mlops_services(path))
        elif first == "cosmo-router" or path.startswith("deploy/helm/charts/cosmo-router/"):
            _add(selected, "cosmo-router")
        elif path == "pom.xml":
            selected.update(SPRING_SERVICES)
        elif path.startswith("deploy/helm/charts/"):
            chart = path.split("/", 2)[2].split("/", 1)[0]
            if chart in RELEASE_SERVICES:
                _add(selected, chart)
        elif path.startswith("deploy/helm/microservices-umbrella/") or path.startswith("deploy/helm/values/"):
            selected.update(CI_SERVICES)
        elif path.startswith("docs/reference/contracts/events/"):
            if path.endswith("order-event.schema.json"):
                selected.update({"orders-service", "payments-service", "inventory-service"})
            elif path.endswith("payment-event.schema.json"):
                selected.update({"payments-service", "orders-service"})
            elif path.endswith("fulfillment-event.schema.json"):
                selected.update({"fulfillment-service", "orders-service"})
            else:
                selected.update(RELEASE_SERVICES)
        elif path.startswith(".github/workflows/") or path.startswith("devsecops/"):
            workflow_name = PurePosixPath(path).name
            if workflow_name.startswith("service-") and workflow_name.endswith(".yml"):
                service = workflow_name.removeprefix("service-").removesuffix(".yml")
                service = {
                    "payments": "payments-service",
                    "orders": "orders-service",
                    "products": "products-service",
                    "inventory": "inventory-service",
                    "notifications": "notification-service",
                    "fulfillment": "fulfillment-service",
                    "analytics": "analytics-service",
                }.get(service, service)
                if service in CI_SERVICES:
                    _add(selected, service)
                else:
                    selected.update(CI_SERVICES)
            else:
                selected.update(CI_SERVICES)

    return [service for service in CI_SERVICES if service in selected]


def release_services(paths: list[str]) -> list[str]:
    """Return images whose build inputs changed; config/docs do not rebuild images."""
    selected: set[str] = set()
    for raw_path in paths:
        path = str(PurePosixPath(raw_path))
        first = path.split("/", 1)[0]
        if first in RELEASE_SERVICES and "/" in path:
            _add(selected, first)
        elif first == "mlops":
            selected.update(_mlops_services(path))
        elif path == "pom.xml":
            selected.update(SPRING_SERVICES)
        elif path.startswith("docs/reference/contracts/events/"):
            selected.update(
                set(affected_services([path])) & set(RELEASE_SERVICES)
            )
    return [service for service in RELEASE_SERVICES if service in selected]


def changed_paths(base_ref: str, head_ref: str, cwd: str | None = None) -> list[str]:
    if not base_ref or not head_ref:
        raise ValueError("both base and head refs are required")
    for ref in (base_ref, head_ref):
        subprocess.run(
            ["git", "rev-parse", "--verify", f"{ref}^{{commit}}"],
            cwd=cwd,
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRTD", f"{base_ref}...{head_ref}"],
        check=True, capture_output=True, text=True, cwd=cwd,
    )
    return result.stdout.splitlines()


def matrix_for_services(services: list[str]) -> list[dict[str, str]]:
    return [
        {"service-name": service, **SERVICE_WORKFLOW[service]}
        for service in services
        if service != "cosmo-router"
    ]


def requires_infrastructure_checks(paths: list[str]) -> bool:
    return any(
        path.startswith(("terraform/", "deploy/helm/", "deploy/kubernetes/", "argocd/", "devsecops/policies/conftest/"))
        for path in paths
    )


def requires_security_checks(paths: list[str]) -> bool:
    dependency_names = {
        "pom.xml", "go.mod", "go.sum", "package.json", "package-lock.json",
        "pnpm-lock.yaml", "yarn.lock", "poetry.lock", "uv.lock", ".snyk",
        ".trivyignore", ".gitleaksignore",
    }
    return any(
        PurePosixPath(path).name in dependency_names
        or PurePosixPath(path).name.startswith("requirements") and path.endswith(".txt")
        or PurePosixPath(path).name.startswith("Dockerfile")
        or path.startswith(("devsecops/", "deploy/helm/"))
        or path.startswith(".github/workflows/")
        for path in paths
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("ci", "release"), default="ci")
    parser.add_argument("--base-ref", required=True)
    parser.add_argument("--head-ref", required=True)
    parser.add_argument("--all", action="store_true", help="select every releaseable service")
    parser.add_argument("--matrix", action="store_true", help="emit service workflow inputs")
    parser.add_argument("--infrastructure-checks", action="store_true")
    parser.add_argument("--security-checks", action="store_true")
    args = parser.parse_args()
    if args.all:
        selected = list(RELEASE_SERVICES if args.mode == "release" else CI_SERVICES)
        payload = matrix_for_services(selected) if args.matrix else selected
        print(json.dumps(payload, separators=(",", ":")))
        return 0
    try:
        paths = changed_paths(args.base_ref, args.head_ref)
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(f"Could not determine changed files: {exc}", file=sys.stderr)
        return 2

    if args.infrastructure_checks:
        print(json.dumps(requires_infrastructure_checks(paths)))
        return 0
    if args.security_checks:
        print(json.dumps(requires_security_checks(paths)))
        return 0

    selected = release_services(paths) if args.mode == "release" else affected_services(paths)
    payload = matrix_for_services(selected) if args.matrix else selected
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
