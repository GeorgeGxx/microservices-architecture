#!/usr/bin/env python3
"""
Selective Change Detection Matrix for Multi-Cloud CI/CD Pipelines
(GitHub Actions / AWS EKS, Azure DevOps / Azure AKS, Bitbucket Pipelines / GCP GKE)

Evaluates git diff paths (or explicit file lists) and outputs a structured JSON matrix
indicating which microservices, GraphQL subgraphs, Helm charts, Terraform modules,
or platform components require build, test, and deployment.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Set, Dict, List

ALL_SERVICES: List[str] = [
    "products-service",
    "orders-service",
    "inventory-service",
    "notification-service",
    "payments-service",
    "fulfillment-service",
    "analytics-service",
    "ai-service",
    "demand-forecast-service",
    "frontend",
    "cosmo-router",
]

SUBGRAPH_TO_SERVICE: Dict[str, List[str]] = {
    "cosmo-router/subgraphs/products.graphql": ["products-service", "cosmo-router"],
    "cosmo-router/subgraphs/orders.graphql": ["orders-service", "cosmo-router"],
    "cosmo-router/subgraphs/inventory.graphql": ["inventory-service", "cosmo-router"],
}

GLOBAL_SHARED_PREFIXES: tuple[str, ...] = (
    "helm/charts/microservice/",
    "contracts/",
    ".github/workflows/_",
    "azure-devops/templates/",
)


def classify_changed_paths(paths: Iterable[str]) -> Dict[str, object]:
    normalized = [p.strip().replace("\\", "/").lstrip("./") for p in paths if p and p.strip()]
    impacted_services: Set[str] = set()
    terraform_changed = False
    helm_changed = False
    cosmo_changed = False
    istio_changed = False
    docs_only = bool(normalized)

    for path in normalized:
        is_doc = path.endswith(".md") or path.startswith("docs/") or path.startswith("reports/")
        if not is_doc:
            docs_only = False

        if any(path.startswith(prefix) for prefix in GLOBAL_SHARED_PREFIXES):
            impacted_services.update(ALL_SERVICES)
            helm_changed = helm_changed or path.startswith("helm/")
            continue

        if path in SUBGRAPH_TO_SERVICE:
            impacted_services.update(SUBGRAPH_TO_SERVICE[path])
            cosmo_changed = True
            continue

        if path.startswith("cosmo-router/") or path.startswith("helm/charts/cosmo-router/"):
            impacted_services.add("cosmo-router")
            cosmo_changed = True
            helm_changed = helm_changed or path.startswith("helm/")
            continue

        if path.startswith("mlops/"):
            impacted_services.add("demand-forecast-service")
            continue

        for svc in ALL_SERVICES:
            if path.startswith(f"{svc}/"):
                impacted_services.add(svc)
                break

        if path.startswith("terraform/"):
            terraform_changed = True
        if path.startswith("helm/"):
            helm_changed = True
        if path.startswith("k8s/istio/"):
            istio_changed = True

    ordered_services = [svc for svc in ALL_SERVICES if svc in impacted_services]
    return {
        "changed_files_count": len(normalized),
        "docs_only": docs_only,
        "run_all_services": len(ordered_services) == len(ALL_SERVICES),
        "services": ordered_services,
        "cosmo_router_changed": cosmo_changed or ("cosmo-router" in impacted_services),
        "helm_changed": helm_changed,
        "terraform_changed": terraform_changed,
        "istio_changed": istio_changed,
    }


def get_git_changed_files(base_ref: str, head_ref: str) -> List[str]:
    cmd = ["git", "diff", "--name-only", f"{base_ref}...{head_ref}"]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        cmd_fallback = ["git", "diff", "--name-only", base_ref, head_ref]
        proc = subprocess.run(cmd_fallback, capture_output=True, text=True, check=True)
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect impacted microservices and infrastructure components.")
    parser.add_argument("--base", default="HEAD~1", help="Base git ref for diff comparison")
    parser.add_argument("--head", default="HEAD", help="Head git ref for diff comparison")
    parser.add_argument("--files", nargs="*", help="Explicit list of changed file paths (bypasses git diff)")
    args = parser.parse_args()

    if args.files is not None:
        files = args.files
    else:
        files = get_git_changed_files(args.base, args.head)

    result = classify_changed_paths(files)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
