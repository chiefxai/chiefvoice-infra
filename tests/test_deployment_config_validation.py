from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from sync_chiefvoice_deployment_config import validate_deployment_values


def valid_values(substitutions: object) -> dict:
    return validate_deployment_values(
        project_id="chiefvoice-service",
        region="asia-south1",
        provider=(
            "projects/577933119654/locations/global/"
            "workloadIdentityPools/chiefvoice-service/providers/github"
        ),
        cloud_build_service_account="chiefvoice-build@chiefvoice-service.iam.gserviceaccount.com",
        substitutions=substitutions,
        github_deploy_service_account="chiefvoice-github-deploy@chiefvoice-service.iam.gserviceaccount.com",
        project_number="577933119654",
    )


class DeploymentConfigValidationTests(unittest.TestCase):
    def test_valid_terraform_outputs_are_accepted(self):
        self.assertEqual(valid_values({"_REGION": "asia-south1"}), {"_REGION": "asia-south1"})

    def test_empty_substitution_is_rejected_before_sync(self):
        with self.assertRaisesRegex(RuntimeError, "substitution _OIDC_CLIENT_ID is empty"):
            valid_values({"_REGION": "asia-south1", "_OIDC_CLIENT_ID": "  "})

    def test_malformed_workload_identity_output_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "invalid Workload Identity Provider"):
            validate_deployment_values(
                "chiefvoice-service",
                "asia-south1",
                "workloadIdentityPools/chiefvoice-service/providers/github",
                "chiefvoice-build@chiefvoice-service.iam.gserviceaccount.com",
                {"_REGION": "asia-south1"},
                "chiefvoice-github-deploy@chiefvoice-service.iam.gserviceaccount.com",
                "577933119654",
            )

    def test_malformed_substitution_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid Cloud Build substitution key"):
            valid_values({"_bad key": "value"})

    def test_provider_project_number_must_match_terraform_project_output(self):
        with self.assertRaisesRegex(RuntimeError, "belongs to a different project"):
            validate_deployment_values(
                "chiefvoice-service",
                "asia-south1",
                (
                    "projects/123456789012/locations/global/"
                    "workloadIdentityPools/chiefvoice-service/providers/github"
                ),
                "chiefvoice-build@chiefvoice-service.iam.gserviceaccount.com",
                {"_REGION": "asia-south1"},
                "chiefvoice-github-deploy@chiefvoice-service.iam.gserviceaccount.com",
                "577933119654",
            )


if __name__ == "__main__":
    unittest.main()
