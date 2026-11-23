import unittest
import subprocess
import tempfile
from pathlib import Path

from scripts.release_service_detector import (
    CI_SERVICES,
    RELEASE_SERVICES,
    affected_services,
    matrix_for_services,
    requires_infrastructure_checks,
    requires_security_checks,
    release_services,
    changed_paths,
)


class ReleaseServiceDetectorTests(unittest.TestCase):
    def test_service_source_change_selects_only_that_service(self):
        paths = ["payments-service/internal/kafka/consumer.go"]
        self.assertEqual(affected_services(paths), ["payments-service"])
        self.assertEqual(release_services(paths), ["payments-service"])

    def test_maven_parent_change_selects_only_maven_services(self):
        self.assertEqual(
            affected_services(["pom.xml"]),
            ["products-service", "orders-service", "inventory-service", "notification-service"],
        )

    def test_maven_parent_releases_only_maven_images(self):
        self.assertEqual(
            release_services(["pom.xml"]),
            ["products-service", "orders-service", "inventory-service", "notification-service"],
        )

    def test_mlops_specific_and_shared_changes(self):
        self.assertEqual(
            affected_services(["mlops/Dockerfile.forecast"]), ["demand-forecast"]
        )
        self.assertEqual(
            release_services(["mlops/Dockerfile.training"]), ["mlops-training"]
        )
        self.assertEqual(
            affected_services(["mlops/data_contracts.py"]),
            ["demand-forecast", "mlops-training"],
        )
        self.assertEqual(
            set(affected_services(["mlops/new_shared_component.py"])),
            {"demand-forecast", "mlops-training", "mlflow"},
        )

    def test_event_contract_changes_select_consumers(self):
        self.assertEqual(
            set(release_services(["docs/reference/contracts/events/order-event.schema.json"])),
            {"orders-service", "payments-service", "inventory-service"},
        )

    def test_workflow_change_runs_ci_without_rebuilding_images(self):
        self.assertEqual(
            affected_services([".github/workflows/docker-release.yml"]), list(CI_SERVICES)
        )
        self.assertEqual(release_services([".github/workflows/docker-release.yml"]), [])

    def test_service_workflow_change_runs_only_that_service(self):
        path = ".github/workflows/service-payments.yml"
        self.assertEqual(affected_services([path]), ["payments-service"])
        self.assertTrue(requires_security_checks([path]))

    def test_helm_chart_change_runs_its_checks_without_rebuilding_image(self):
        path = "deploy/helm/charts/payments-service/templates/deployment.yaml"
        self.assertEqual(affected_services([path]), ["payments-service"])
        self.assertEqual(release_services([path]), [])

    def test_umbrella_values_validate_all_services_but_do_not_rebuild_images(self):
        self.assertEqual(
            affected_services(["deploy/helm/microservices-umbrella/values.yaml"]),
            list(CI_SERVICES),
        )
        self.assertEqual(release_services(["deploy/helm/values/values-eks-dev.yaml"]), [])

    def test_unknown_docs_change_does_not_schedule_service_ci_or_release(self):
        self.assertEqual(affected_services(["docs/02-operations/README.md"]), [])
        self.assertEqual(release_services(["docs/02-operations/README.md"]), [])

    def test_service_matrix_has_reusable_workflow_inputs(self):
        matrix = matrix_for_services(["payments-service", "demand-forecast"])
        self.assertEqual(matrix[0]["service-type"], "go")
        self.assertEqual(matrix[0]["dockerfile-path"], "payments-service/Dockerfile")
        self.assertEqual(matrix[1]["helm-values-key"], "mlops.forecast")

    def test_cosmo_router_has_a_dedicated_validation_workflow(self):
        self.assertNotIn(
            "cosmo-router", [item["service-name"] for item in matrix_for_services(["cosmo-router"])]
        )
        self.assertTrue(requires_infrastructure_checks(["deploy/helm/charts/cosmo-router/Chart.yaml"]))

    def test_infrastructure_changes_request_the_infrastructure_gate(self):
        self.assertTrue(requires_infrastructure_checks(["terraform/environments/aws/main.tf"]))
        self.assertTrue(requires_infrastructure_checks(["argocd/application-dev.yaml"]))
        self.assertFalse(requires_infrastructure_checks(["payments-service/internal/service.go"]))

    def test_dependency_and_security_policy_changes_request_security_scan(self):
        self.assertTrue(requires_security_checks(["payments-service/go.mod"]))
        self.assertTrue(requires_security_checks(["devsecops/sast/semgrep/rules.yaml"]))
        self.assertFalse(requires_security_checks(["docs/02-operations/recovery.md"]))

    def test_release_service_list_includes_ai_but_not_external_router_image(self):
        self.assertIn("ai-service", RELEASE_SERVICES)
        self.assertNotIn("cosmo-router", RELEASE_SERVICES)

    def test_mlflow_dockerfile_only_selects_mlflow(self):
        self.assertEqual(affected_services(["mlops/Dockerfile"]), ["mlflow"])
        self.assertEqual(release_services(["mlops/Dockerfile"]), ["mlflow"])

    def test_changed_paths_uses_git_three_dot_diff(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
            (repo / "payments-service").mkdir()
            tracked_file = repo / "payments-service" / "source.go"
            tracked_file.write_text("package payments\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-qm", "base"], cwd=repo, check=True)
            base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            tracked_file.write_text("package payments\n// changed\n", encoding="utf-8")
            subprocess.run(["git", "commit", "-qam", "change"], cwd=repo, check=True)
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            self.assertEqual(changed_paths(base, head, cwd=directory), ["payments-service/source.go"])


if __name__ == "__main__":
    unittest.main()
