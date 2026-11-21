# Chiefvoice infrastructure

Terraform-managed GCP production infrastructure for Chiefvoice. The active Terraform root is [`gcp/`](gcp/README.md). It provisions the VM and PostgreSQL, Cloud Tasks, the post-call Cloud Function, storage, secrets, and IAM.

The app source and Cloud Build release pipeline remain in [chiefvoice](https://github.com/chiefxai/chiefvoice). See [GCP setup and apply instructions](gcp/README.md) before running Terraform. Terraform state and production `terraform.tfvars` contain secrets and must never be committed.

The manual regional migration workflow is [`.github/workflows/terraform-gcp-region.yml`](.github/workflows/terraform-gcp-region.yml). It requires the protected `production` environment and explicit data-discard confirmation.
