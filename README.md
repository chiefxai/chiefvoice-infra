# Chiefvoice infrastructure

This repository keeps both the active GCP production stack and a future AWS alternative. The active Terraform root is [`gcp/`](gcp/README.md); [`aws/`](aws/README.md) is an independent, inactive EC2/SQS/Lambda option and must not be applied as part of GCP operations.

The app source and Cloud Build release pipeline remain in [chiefvoice](https://github.com/chiefxai/chiefvoice). See [GCP setup and apply instructions](gcp/README.md) before running Terraform. Terraform state and production `terraform.tfvars` contain secrets and must never be committed.

Each root requires a separate backend and state. AWS has no deployment workflow and is not provisioned by GCP CI. The manual GCP regional migration workflow is [`.github/workflows/terraform-gcp-region.yml`](.github/workflows/terraform-gcp-region.yml). It requires the protected `production` environment and explicit data-discard confirmation.
