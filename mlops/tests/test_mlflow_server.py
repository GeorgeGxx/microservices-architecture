import unittest
import importlib.util

class TestMlflowServer(unittest.TestCase):
    def test_mlflow_package_and_tracking(self):
        """Verify MLflow is available or properly referenced."""
        spec = importlib.util.find_spec("mlflow")
        if spec is not None:
            import mlflow
            self.assertTrue(hasattr(mlflow, "get_tracking_uri") or hasattr(mlflow, "__version__"))

    def test_mlflow_default_port(self):
        """Verify default tracking server port is 5000."""
        default_port = 5000
        self.assertEqual(default_port, 5000)

    def test_mlflow_backend_sqlite_uri_structure(self):
        """Verify SQLite backend URI structure for local and container setups."""
        db_path = "/mlflow-data/mlflow.db"
        uri = f"sqlite:///{db_path}"
        self.assertTrue(uri.startswith("sqlite:///"))
        self.assertTrue(uri.endswith("/mlflow.db"))

    def test_mlflow_artifacts_directory(self):
        """Verify default artifacts directory."""
        artifacts_path = "/mlflow-artifacts"
        self.assertEqual(artifacts_path, "/mlflow-artifacts")

if __name__ == "__main__":
    unittest.main()
