#!/usr/bin/env python3
"""MLOps TDD Test Suite Runner.

Executes unit, data contract, feature engineering, and model invariant tests
with coverage metrics and failure diagnoses.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path


def run_tdd_suite() -> int:
    mlops_dir = Path(__file__).resolve().parent
    tests_dir = mlops_dir / "tests"

    # Ensure mlops_dir is at the front of sys.path
    if str(mlops_dir) not in sys.path:
        sys.path.insert(0, str(mlops_dir))
    os.environ["PYTHONPATH"] = str(mlops_dir)

    print("================================================================================")
    print(" [TDD] MLOps Test-Driven Development Quality Suite")
    print(f" Directory: {mlops_dir}")
    print(" Levels   : [1] Data Contracts | [2] Feature Eng | [3] Model Invariants | [4] API")
    print("================================================================================")

    loader = unittest.TestLoader()
    suite = loader.discover(start_dir=str(tests_dir), pattern="test_*.py")

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("--------------------------------------------------------------------------------")
    print(f" Tests Run : {result.testsRun}")
    print(f" Failures  : {len(result.failures)}")
    print(f" Errors    : {len(result.errors)}")
    print(f" Status    : {'[PASS] ALL TESTS GREEN (TDD GREEN)' if result.wasSuccessful() else '[FAIL] TESTS FAILED (TDD RED)'}")
    print("================================================================================")

    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(run_tdd_suite())
