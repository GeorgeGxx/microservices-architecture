#!/usr/bin/env python3
"""Unit tests for scripts/detect-changed-services.py."""

import importlib.util
from pathlib import Path
import unittest

SCRIPT_PATH = Path(__file__).resolve().parent / "detect-changed-services.py"
spec = importlib.util.spec_from_file_location("detect_changed_services", SCRIPT_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class DetectChangedServicesTests(unittest.TestCase):
    def test_single_service_change(self):
        res = module.classify_changed_paths(["payments-service/internal/services/payment_service.go"])
        self.assertEqual(res["services"], ["payments-service"])
        self.assertFalse(res["docs_only"])
        self.assertFalse(res["run_all_services"])

    def test_subgraph_schema_change_triggers_service_and_router(self):
        res = module.classify_changed_paths(["cosmo-router/subgraphs/orders.graphql"])
        self.assertEqual(res["services"], ["orders-service", "cosmo-router"])
        self.assertTrue(res["cosmo_router_changed"])

    def test_shared_helm_chart_triggers_all_services(self):
        res = module.classify_changed_paths(["helm/charts/microservice/templates/deployment.yaml"])
        self.assertTrue(res["run_all_services"])
        self.assertTrue(res["helm_changed"])
        self.assertEqual(len(res["services"]), len(module.ALL_SERVICES))

    def test_docs_only_change(self):
        res = module.classify_changed_paths(["README.md", "docs/architecture.md"])
        self.assertTrue(res["docs_only"])
        self.assertEqual(res["services"], [])


if __name__ == "__main__":
    unittest.main()
