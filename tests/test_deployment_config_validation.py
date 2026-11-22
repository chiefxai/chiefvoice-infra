from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from sync_chiefvoice_deployment_config import validate_deployment_values


def valid_values(substitutions: object) -> dict:
    return validate_deployment_values(
        project_id="sample-project-123",
        region="asia-southeast1",
        provider=(
            "projects/123456789012/locations/global/"
            "workloadIdentityPools/github-actions/providers/chiefvoice-production"
        ),
        cloud_build_service_account="chiefvoice-build@sample-project-123.iam.gserviceaccount.com",
        substitutions=substitutions,
    )


def test_valid_terraform_outputs_are_accepted():
    assert valid_values({"_REGION": "asia-southeast1"}) == {
        "_REGION": "asia-southeast1"
    }


def test_empty_substitution_is_rejected_before_sync():
    with pytest.raises(RuntimeError, match="substitution _OIDC_CLIENT_ID is empty"):
        valid_values({"_REGION": "asia-southeast1", "_OIDC_CLIENT_ID": "  "})


def test_malformed_workload_identity_output_is_rejected():
    with pytest.raises(RuntimeError, match="invalid Workload Identity Provider"):
        validate_deployment_values(
            "sample-project-123",
            "asia-southeast1",
            "workloadIdentityPools/github-actions/providers/chiefvoice-production",
            "chiefvoice-build@sample-project-123.iam.gserviceaccount.com",
            {"_REGION": "asia-southeast1"},
        )


def test_malformed_substitution_is_rejected():
    with pytest.raises(RuntimeError, match="Invalid Cloud Build substitution key"):
        valid_values({"_bad key": "value"})
