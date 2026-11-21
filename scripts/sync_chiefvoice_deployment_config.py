#!/usr/bin/env python3
"""Sync non-secret Terraform deployment outputs to chiefvoice Actions variables."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


API_ROOT = "https://api.github.com"
REPOSITORY = "chiefxai/chiefvoice"
VARIABLES_PATH = f"/repos/{REPOSITORY}/actions/variables"
MAX_VARIABLE_BYTES = 48 * 1024


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


def main() -> None:
    token = required_env("CHIEFVOICE_REPO_VARIABLES_TOKEN")
    project_id = required_env("GCP_PROJECT_ID")
    region = required_env("GCP_REGION")
    provider = required_env("GCP_WORKLOAD_IDENTITY_PROVIDER")
    cloud_build_service_account = required_env("GCP_CLOUD_BUILD_SERVICE_ACCOUNT")
    substitutions_path = Path(required_env("CLOUDBUILD_SUBSTITUTIONS_FILE"))
    substitutions = json.loads(substitutions_path.read_text(encoding="utf-8"))
    if not isinstance(substitutions, dict) or not substitutions:
        raise RuntimeError("Terraform returned an empty Cloud Build substitutions map")
    for key, value in substitutions.items():
        if not isinstance(key, str) or not key.startswith("_"):
            raise RuntimeError(f"Invalid Cloud Build substitution key: {key!r}")
        if not isinstance(value, (str, int, float, bool)):
            raise RuntimeError(f"Invalid Cloud Build substitution value for {key}")
        if "\n" in str(value) or "\r" in str(value):
            raise RuntimeError(f"Cloud Build substitution {key} contains a newline")

    values = {
        "GCP_PROJECT_ID": project_id,
        "GCP_REGION": region,
        "GCP_WORKLOAD_IDENTITY_PROVIDER": provider,
        "GCP_CLOUD_BUILD_SERVICE_ACCOUNT": cloud_build_service_account,
        "GCP_CLOUDBUILD_SUBSTITUTIONS_JSON": json.dumps(
            substitutions, sort_keys=True, separators=(",", ":")
        ),
    }
    collection = VARIABLES_PATH
    for name, value in values.items():
        if len(value.encode("utf-8")) > MAX_VARIABLE_BYTES:
            raise RuntimeError(f"GitHub Actions variable exceeds the 48 KB limit: {name}")
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
