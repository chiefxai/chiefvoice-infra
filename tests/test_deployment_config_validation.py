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

    def test_cloud_build_outputs_use_direct_vpc_network_and_subnet(self):
        outputs = (Path(__file__).resolve().parents[1] / "gcp" / "outputs.tf").read_text(
            encoding="utf-8"
        )
        main = (Path(__file__).resolve().parents[1] / "gcp" / "main.tf").read_text(
            encoding="utf-8"
        )
        self.assertIn('_FUNCTION_NETWORK                        = google_compute_network.main.name', outputs)
        self.assertIn(
            '_FUNCTION_SUBNET                         = google_compute_subnetwork.function_egress.name',
            outputs,
        )
        self.assertNotIn("FUNCTION_VPC_CONNECTOR", outputs)
        self.assertNotIn("google_vpc_access_connector", outputs)
        self.assertIn('ip_cidr_range            = "10.8.1.0/26"', main)
        postgres_firewall = main.split(
            'resource "google_compute_firewall" "postgres_from_tasks" {', 1
        )[1].split("\n}", 1)[0]
        self.assertIn(
            "source_ranges = [google_compute_subnetwork.function_egress.ip_cidr_range]",
            postgres_firewall,
        )
        self.assertIn('ports    = ["5432"]', postgres_firewall)
        self.assertNotIn("0.0.0.0/0", postgres_firewall)


if __name__ == "__main__":
    unittest.main()
