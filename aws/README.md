# AWS VM deployment (future option; not currently deployed)

This independent Terraform root describes a possible future AWS deployment. GCP remains the active production environment; do not apply this root until an AWS migration and cutover plan is approved. Applying it would create a separate AWS environment and would not migrate GCP data. It runs the API and PostgreSQL together on one EC2 VM. SQS queues post-call work for an image-based Lambda in a private subnet. Recordings and encrypted PostgreSQL backups use a private S3 bucket. The database lives on the VM's encrypted EBS volume; there is no RDS instance in this active topology.

## Prerequisites

- Supply an Ubuntu 24.04 AMI, prebuilt API and Lambda image URIs, globally unique S3 bucket name, restricted SSH CIDR and public DNS name. Point `public_domain` to the `backend_public_ip` Elastic IP before the first public deployment. Caddy terminates TLS and provider callback URLs use HTTPS.
- Configure OIDC issuer, audience and JWKS URL. Vertex project creation also requires a Google service-account JSON secret in AWS Secrets Manager. Give the account the configured GCP folder/org and billing-account permissions. The VM mounts the JSON as a root-readable file; the Lambda retrieves the same secret by ARN.
- Set `platform_admin_subjects` to the trusted OIDC `sub` values for platform operators. Provisioning endpoints additionally require `platform:customers:write` or `platform:customers:read` token scopes; an empty allowlist disables customer administration.
- Keep Terraform state encrypted and access restricted: it contains Secrets Manager secret versions for the DB password, Fernet keys and Vobiz secrets, plus bootstrap configuration. EC2 retrieves runtime values through its role and writes them to root-only files; user data carries secret ARNs, not those values.

## Apply

From this directory, copy the examples and replace their placeholders before initializing Terraform:

```sh
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

The examples are not complete configurations. In `terraform.tfvars`, set every required variable in `variables.tf` that has no default. This includes the Ubuntu AMI, restricted SSH CIDR, API and Lambda image URIs, public domain, OIDC issuer/audience/JWKS URL, GCP project parent, billing account, runtime service account, budget project, Google credential secret ARN, and globally unique object bucket name. The backend file needs an already-created private S3 bucket and DynamoDB lock table. Use AWS credentials with access to that backend and to the resources in this root. The Google service-account JSON referenced by `google_credentials_secret_arn` must be available in AWS Secrets Manager and authorized for the configured GCP project/billing operations. Do not commit either populated file.

```sh
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

The VM role pulls ECR images and accesses the S3 bucket and SQS queue. PostgreSQL port 5432 is allowed only from the Lambda security group. Caddy is the only public application entry point (ports 80/443); SSH is restricted by `ssh_allowed_cidr`. The Elastic IP is stable for DNS.

The first boot starts PostgreSQL, waits for its health check, runs `alembic upgrade head` from the configured API image, then starts API and Caddy. `chiefvoice-deploy IMAGE_URI` repeats the migration before replacing API; do not deploy concurrently because the instance is intentionally a single deployment target. The API's queue dispatcher sends SQS messages and Lambda receives one at a time with a dead-letter queue after bounded retries.

## PostgreSQL backups and restore check

The API creates a daily service-scoped `pg_dump` backup, encrypts it with the dedicated `BACKUP_ENCRYPTION_KEY`, writes it to S3 and expires objects after 30 days. It requires PostgreSQL 16 client tools, installed in the image. EBS snapshots are not a substitute for encrypted, off-instance backups.

Run `sudo chiefvoice-backup-restore-check` on the VM to create a disposable database, verify and restore the newest backup into it, and remove the scratch database when the check exits. Confirm the `restore_verified` log line and inspect the restored schema/data before relying on the backup. Never target the production database.

The older ECS/Fargate and RDS design remains in [`chiefvoice/infra/scalable-infra/aws`](https://github.com/chiefxai/chiefvoice/tree/main/infra/scalable-infra/aws). This EC2/SQS/Lambda root is also an option only; neither AWS topology is currently deployed.
