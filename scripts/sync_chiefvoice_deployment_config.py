#!/usr/bin/env python3
"""Sync non-secret Terraform deployment outputs to chiefvoice Actions variables."""

from __future__ import annotations

import json
import math
import os
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


API_ROOT = "https://api.github.com"
REPOSITORY = "chiefxai/chiefvoice"
VARIABLES_PATH = f"/repos/{REPOSITORY}/actions/variables"
MAX_VARIABLE_BYTES = 48 * 1024
_PROJECT_ID = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
_REGION = re.compile(r"^[a-z]+-[a-z0-9]+[0-9]$")
_SERVICE_ACCOUNT = re.compile(r"^[^@\s]+@[^@\s]+\.iam\.gserviceaccount\.com$")
_SUBSTITUTION_KEY = re.compile(r"^_[A-Z0-9_]+$")
_WORKLOAD_IDENTITY_PROVIDER = re.compile(
    r"^projects/([1-9][0-9]*)/locations/global/"
    r"workloadIdentityPools/[a-z][a-z0-9-]{2,31}/providers/[a-z][a-z0-9-]{2,31}$"
)


def api_request(method: str, path: str, token: str, payload: dict | None = None) -> tuple[int, bytes]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        API_ROOT + path,
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2026-03-10",
            "Content-Type": "application/json",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            return response.status, response.read()
    except HTTPError as error:
        return error.code, error.read()
    except URLError as error:
        raise RuntimeError(f"Could not reach the GitHub API: {error.reason}") from error


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment value is missing: {name}")
    return value


def validate_deployment_values(
    project_id: str,
    region: str,
    provider: str,
    cloud_build_service_account: str,
    substitutions: object,
    github_deploy_service_account: str,
    project_number: str,
) -> dict[str, str | int | float | bool]:
    if not _PROJECT_ID.fullmatch(project_id):
        raise RuntimeError("Terraform returned an invalid GCP project ID")
    if not _REGION.fullmatch(region):
        raise RuntimeError("Terraform returned an invalid GCP region")
    provider_match = _WORKLOAD_IDENTITY_PROVIDER.fullmatch(provider)
    if provider_match is None:
        raise RuntimeError("Terraform returned an invalid Workload Identity Provider resource name")
    if not project_number.isdigit() or project_number.startswith("0"):
        raise RuntimeError("Terraform returned an invalid GCP project number")
    if provider_match.group(1) != project_number:
        raise RuntimeError("Terraform Workload Identity Provider belongs to a different project")
    if not _SERVICE_ACCOUNT.fullmatch(cloud_build_service_account):
        raise RuntimeError("Terraform returned an invalid Cloud Build service account")
    if not _SERVICE_ACCOUNT.fullmatch(github_deploy_service_account):
        raise RuntimeError("Terraform returned an invalid GitHub deploy service account")
    if not github_deploy_service_account.endswith(f"@{project_id}.iam.gserviceaccount.com"):
        raise RuntimeError("Terraform GitHub deploy service account belongs to a different project")
    if not cloud_build_service_account.endswith(f"@{project_id}.iam.gserviceaccount.com"):
        raise RuntimeError("Terraform Cloud Build service account belongs to a different project")
    if not isinstance(substitutions, dict) or not substitutions:
        raise RuntimeError("Terraform returned an empty Cloud Build substitutions map")

    for key, value in substitutions.items():
        if not isinstance(key, str) or not _SUBSTITUTION_KEY.fullmatch(key):
            raise RuntimeError(f"Invalid Cloud Build substitution key: {key!r}")
        if not isinstance(value, (str, int, float, bool)):
            raise RuntimeError(f"Invalid Cloud Build substitution value for {key}")
        if isinstance(value, str):
            if not value.strip():
                raise RuntimeError(f"Cloud Build substitution {key} is empty")
            if value != value.strip():
                raise RuntimeError(f"Cloud Build substitution {key} has surrounding whitespace")
        if isinstance(value, float) and not math.isfinite(value):
            raise RuntimeError(f"Cloud Build substitution {key} is not a finite number")
        if "\n" in str(value) or "\r" in str(value):
            raise RuntimeError(f"Cloud Build substitution {key} contains a newline")
    return substitutions


def main() -> None:
    token = required_env("CHIEFVOICE_REPO_VARIABLES_TOKEN")
    project_id = required_env("GCP_PROJECT_ID")
    region = required_env("GCP_REGION")
    provider = required_env("GCP_WORKLOAD_IDENTITY_PROVIDER")
    cloud_build_service_account = required_env("GCP_CLOUD_BUILD_SERVICE_ACCOUNT")
    github_deploy_service_account = required_env("GCP_GITHUB_DEPLOY_SERVICE_ACCOUNT")
    project_number = required_env("GCP_PROJECT_NUMBER")
    substitutions_path = Path(required_env("CLOUDBUILD_SUBSTITUTIONS_FILE"))
    substitutions = json.loads(substitutions_path.read_text(encoding="utf-8"))
    substitutions = validate_deployment_values(
        project_id,
        region,
        provider,
        cloud_build_service_account,
        substitutions,
        github_deploy_service_account,
        project_number,
    )

    values = {
        "GCP_PROJECT_ID": project_id,
        "GCP_REGION": region,
        "GCP_WORKLOAD_IDENTITY_PROVIDER": provider,
        "GCP_CLOUD_BUILD_SERVICE_ACCOUNT": cloud_build_service_account,
        "GCP_GITHUB_DEPLOY_SERVICE_ACCOUNT": github_deploy_service_account,
        "GCP_CLOUDBUILD_SUBSTITUTIONS_JSON": json.dumps(
            substitutions, sort_keys=True, separators=(",", ":")
        ),
    }
    for name, value in values.items():
        if len(value.encode("utf-8")) > MAX_VARIABLE_BYTES:
            raise RuntimeError(f"GitHub Actions variable exceeds the 48 KB limit: {name}")

    collection = VARIABLES_PATH
    for name, value in values.items():
        encoded_name = quote(name, safe="")
        path = f"{collection}/{encoded_name}"
        status, _ = api_request("GET", path, token)
        if status == 404:
            method, target = "POST", collection
        elif status == 200:
            method, target = "PATCH", path
        else:
            raise RuntimeError(f"GitHub API could not inspect repository variable {name} (HTTP {status})")
        status, _ = api_request(method, target, token, {"name": name, "value": value})
        expected = 201 if method == "POST" else 204
        if status != expected:
            raise RuntimeError(f"GitHub API could not sync repository variable {name} (HTTP {status})")

    print(f"Synchronized {len(values)} non-secret deployment variables to {REPOSITORY}.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(f"Deployment config sync failed: {error}", file=sys.stderr)
        sys.exit(1)
