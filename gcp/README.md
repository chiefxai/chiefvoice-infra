# GCP VM deployment (active topology)

This Terraform root is the active GCP deployment: one Compute Engine VM runs the API and PostgreSQL, Cloud Tasks queues post-call work, and an authenticated second-generation Cloud Function processes jobs. PostgreSQL stays on the VM's encrypted persistent disk. Recordings and encrypted database backups use the private Cloud Storage bucket through its S3-compatible endpoint.

## Prerequisites

Run the commands in this guide from this repository root unless a command explicitly changes directory. The Terraform root is `gcp/`.

- Start Docker Desktop, then authenticate with your own Google account. These commands run gcloud in the provided container and save ADC credentials in the local, Git-ignored `.gcloud/` directory. Complete the Google login in your browser and enter its one-time code in your local terminal; do not send it here. Your account needs permission to manage resources and IAM in `chief-502717` and enable project APIs. Project Owner is the simplest one-time setup role; Terraform creates dedicated runtime and build service accounts for the deployed app.

  ```sh
  mkdir -p .gcloud
  docker compose -f gcp/terraform-compose.yaml run --rm gcloud auth login --no-launch-browser
  docker compose -f gcp/terraform-compose.yaml run --rm gcloud config set project chief-502717
  docker compose -f gcp/terraform-compose.yaml run --rm gcloud auth application-default login --no-launch-browser
  docker compose -f gcp/terraform-compose.yaml run --rm gcloud auth application-default set-quota-project chief-502717
  ```

- Bootstrap the private, versioned Terraform state bucket before initializing the production GCS backend:

  ```sh
  docker compose -f gcp/terraform-compose.yaml run --rm terraform -chdir=state init
  docker compose -f gcp/terraform-compose.yaml run --rm terraform -chdir=state plan
  docker compose -f gcp/terraform-compose.yaml run --rm terraform -chdir=state apply
  cp gcp/backend.hcl.example gcp/backend.hcl
  cp gcp/terraform.tfvars.example gcp/terraform.tfvars
  ```

  The state bucket stack uses local state only to create that bucket; subsequent production state is kept in GCS. The bucket is private and protected from accidental Terraform destruction.
- Ensure billing is active on `chief-502717` under the supplied billing account. This shared-project deployment does not attach customer projects to the billing account.
- The VM and supporting infrastructure can be provisioned before Auth0 is configured. With empty OIDC values the API fails closed and the console cannot sign in; finish Auth0 setup and rerun Terraform plus Cloud Build before using the service.
- Set `public_domain` to a DNS name you control. Point its A record to `backend_external_ip` before the first public deployment so Caddy can obtain/renew its HTTPS certificate. Provider callback URLs are HTTPS.
- Configure OIDC authority, client ID, issuer, audience and JWKS URL; `terraform.tfvars.example` shows the values. Leave them empty only for infrastructure-only bootstrap.
- Set `platform_admin_subjects` to trusted OIDC `sub` values for platform operators. Customer provisioning also requires `platform:customers:write` or `platform:customers:read` in the token scope; an empty allowlist disables customer administration.
- This no-organization deployment uses the hosting project for Vertex AI. Customer records, API keys and call data remain tenant-scoped in PostgreSQL, but Vertex project-level usage and spend caps are shared. The backend and post-call function identities receive Vertex AI access only in this project. Per-customer Vertex project isolation requires a GCP folder/organization or manually provisioned customer projects and a later integration change.
- Terraform creates the `chiefvoice-build` service account and exposes the deployment-specific Cloud Build substitutions as an output. The app deployment workflow passes these values on every build; do not maintain a separate Cloud Build trigger with stale substitutions.
- The app deployment workflow is `chiefxai/chiefvoice/.github/workflows/deploy-gcp.yml`. After a successful Terraform apply, the infra workflows synchronize `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_CLOUD_BUILD_SERVICE_ACCOUNT`, and `GCP_CLOUDBUILD_SUBSTITUTIONS_JSON` into the `chiefxai/chiefvoice` repository. These are non-secret configuration outputs; Cloud Build receives the complete substitutions map at deploy time.
- Use `.github/workflows/terraform-apply-gcp.yml` for normal GCP changes. It creates an encrypted plan, shows the resource actions, and applies only when you choose `yes` and the protected `production` environment approves it. The post-apply step updates the app repository variables automatically. Direct local Terraform applies do not run that sync step; use `.github/workflows/sync-gcp-app-config.yml` afterward to refresh the app repository variables.
- In `chiefxai/chiefvoice-infra`, configure repository variables `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_TF_STATE_BUCKET=chiefvoice-tfstate-297803100712`, and `GCP_TF_STATE_PREFIX=chiefvoice/prod`. Configure repository secrets `GCP_TERRAFORM_TFVARS` and `GCP_TF_PLAN_ENCRYPTION_KEY`. Create a protected `production` environment with required reviewers and add environment secret `CHIEFVOICE_REPO_VARIABLES_TOKEN`: a fine-grained GitHub token limited to `chiefxai/chiefvoice` with **Variables: write** permission. The token lets infra Actions update only the app repo’s deployment variables.
- The first infra Actions run requires the `github_infra_repository` Workload Identity Federation trust to have been applied once using administrator ADC, because GitHub Actions cannot authenticate to GCP before that trust exists. The existing regional migration workflow also synchronizes the app repo variables after its approved apply.
- The one-click output sync workflow is `.github/workflows/sync-gcp-app-config.yml`; run it after an emergency local Terraform apply or to repair stale app variables. A separate, manual full-region migration workflow is available at `.github/workflows/terraform-gcp-region.yml`. It uses the same GitHub OIDC identity and Terraform GCS state. It requires `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_TF_STATE_BUCKET`, `GCP_TF_STATE_PREFIX`, secrets `GCP_TERRAFORM_TFVARS` and `GCP_TF_PLAN_ENCRYPTION_KEY`, plus the `production` environment and `CHIEFVOICE_REPO_VARIABLES_TOKEN` secret described above. It creates an encrypted plan and requires explicit confirmation because applying may delete the old VM/database, recordings and backups bucket contents, and queued tasks. It syncs deployment outputs to `chiefvoice` after a successful apply.

  Before GitHub Actions can run Terraform, a project administrator must bootstrap permissions for `chiefvoice-github-deploy`. Terraform declares the same project roles, but the initial grant must be made by an existing administrator. In Cloud Shell, run:

  ```sh
  PROJECT=chief-502717
  DEPLOY_SA=chiefvoice-github-deploy@chief-502717.iam.gserviceaccount.com
  for ROLE in \
    roles/artifactregistry.admin \
    roles/cloudtasks.admin \
    roles/compute.admin \
    roles/iam.serviceAccountAdmin \
    roles/iam.workloadIdentityPoolAdmin \
    roles/resourcemanager.projectIamAdmin \
    roles/secretmanager.admin \
    roles/serviceusage.serviceUsageAdmin \
    roles/storage.admin \
    roles/vpcaccess.admin; do
    gcloud projects add-iam-policy-binding "$PROJECT" \
      --member="serviceAccount:$DEPLOY_SA" --role="$ROLE" --condition=None --quiet
  done
  gcloud iam service-accounts add-iam-policy-binding \
    chiefvoice-backend@chief-502717.iam.gserviceaccount.com \
    --project="$PROJECT" --member="serviceAccount:$DEPLOY_SA" \
    --role=roles/iam.serviceAccountUser --quiet
  gcloud storage buckets add-iam-policy-binding \
    gs://chiefvoice-tfstate-297803100712 \
    --member="serviceAccount:$DEPLOY_SA" --role=roles/storage.objectAdmin
  ```

  This is a powerful production deploy identity: Terraform manages project IAM bindings, so it receives `roles/resourcemanager.projectIamAdmin`. After the protected Terraform workflow applies, it synchronizes the project, region, WIF provider, Cloud Build service account, and Cloud Build substitutions into `chiefvoice`. Change the DNS A record for `chiefvoice.elvoryx.in` to the new `backend_external_ip`, then run the existing Deploy to GCP workflow manually. That Cloud Build run publishes images in Mumbai, deploys the post-call function in Mumbai, initializes the fresh database, and starts the app. The previous function in `us-central1` is outside this Terraform state and should be removed after confirming the Mumbai deployment works. The current Cloud Build pipeline still builds and serves the console on the VM; it does not deploy the frontend to Vercel.
- Protect the Terraform remote state: it contains Secret Manager secret versions for the database password, Fernet keys, Vobiz secrets and HMAC object-storage credentials, as well as the rendered startup script. Runtime startup reads values from Secret Manager into root-only files; instance metadata contains secret IDs rather than those values.

## Apply and deploy

```sh
cd gcp
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Use the protected `terraform-apply-gcp.yml` workflow for routine infrastructure changes so the matching app repository variables are synchronized. A direct local apply does not update GitHub variables automatically.

Terraform reserves a regional static IP; point DNS to the `backend_external_ip` output. VM startup installs Docker, PostgreSQL, Caddy and the Google Cloud CLI, configures Artifact Registry authentication, and starts PostgreSQL. Cloud Build publishes the API image, deploys the post-call function with the Serverless VPC Access connector, binds `roles/run.invoker` only to the Cloud Tasks OIDC service account, obtains the HTTPS function URL, connects to the VM through IAP, waits for PostgreSQL readiness, runs `alembic upgrade head` using the same new image, then starts API and Caddy. The function uses a secret database URL targeting the VM's private address; the connector-only firewall rule allows its PostgreSQL traffic.

Cloud Build builds the API and React console images, deploys the post-call function, applies migrations, and exposes the API and console together on the same HTTPS domain. It also runs unit tests, lint, compilation and public `/healthz`, `/readyz` and `/metrics` probes. The GitHub deployment workflow submits these Cloud Builds after Terraform has created the VM, Artifact Registry repository, connector, queue and service accounts. Later builds repeat migrations under an instance-local deployment lock and only expose the API after migration succeeds.

Post-call transcript review uses Cloud Speech-to-Text Chirp 2 in `asia-southeast1` when the primary transcript needs review. Terraform enables `speech.googleapis.com` and grants the post-call function service account `roles/speech.client` in the hosting project. To use another supported model or region, set `post_call_transcription_model` or `post_call_transcription_location` in `terraform.tfvars`, apply Terraform through the protected workflow; it synchronizes the updated `cloud_build_substitutions` to the app repository and the deploy workflow passes them to Cloud Build. Cloud Speech usage is billed separately from Vertex AI.

For a manual VM-only deployment (for example, a change confined to the API or console), SSH to the VM and run the repository script. The VM startup installs Docker but may not install Git, so install it if needed. Keep the checkout beside `/opt/chiefvoice/compose.yaml`; the script uses that compose directory for the running services:

```sh
gcloud compute ssh chiefvoice-backend --project=chief-502717 --zone=asia-south1-a --tunnel-through-iap
sudo apt-get update && sudo apt-get install -y git # only if git is missing
sudo git clone https://github.com/chiefxai/chiefvoice.git /opt/chiefvoice/source # first deployment only
cd /opt/chiefvoice/source
sudo bash deploy.sh main
```

For later deployments, run `cd /opt/chiefvoice/source && sudo bash deploy.sh main`. The script fast-forwards to `origin/main`, builds the API and console images on the VM, applies migrations, restarts the services, and checks the public health endpoint. It shares the VM deployment lock with Cloud Build, so concurrent deployments wait for each other. This VM-only path does not deploy changes under `deploy/gcp/post-call-function/`; use Cloud Build for those changes or for the full production validation sequence. Frontend OIDC build values can be overridden with `VITE_OIDC_AUTHORITY`, `VITE_OIDC_CLIENT_ID`, `VITE_OIDC_AUDIENCE`, and `VITE_OIDC_SCOPE`; `HEALTHCHECK_URL` changes the final health probe.

For Auth0, configure an API audience (for example `https://chiefvoice.elvoryx.in/api`) and a single-page application whose allowed callback and web origin are `https://chiefvoice.elvoryx.in`. Create an Auth0 Action that adds the configured namespaced tenant claim (default `https://chiefvoice.elvoryx.in/tenant_id`) to access tokens. Request the `platform:customers:read` and `platform:customers:write` API permissions. Set the OIDC authority, client ID, issuer, audience, JWKS URL, and your Auth0 user `sub` in `terraform.tfvars`; the output carries the console settings into Cloud Build on the next app deployment.

## Backup and restore

The API periodically takes service-scoped PostgreSQL backups with `pg_dump`, encrypts the archive using the dedicated `BACKUP_ENCRYPTION_KEY`, and stores the encrypted object in the private bucket. Policy is one day interval and 30 day retention. The VM service account has object access; the bucket enforces uniform access and public access prevention. Backups require no extra host cron job because the API's backup runner performs the scheduled work.

Check a restore by running `sudo chiefvoice-backup-restore-check` on the VM. It creates a disposable database, verifies and decrypts the newest backup into it, and drops that database on exit. Confirm the `restore_verified` log line and then verify the restored database schema/data before treating a backup as usable. Never restore to the production database. The container image includes PostgreSQL 16 client tools used by the backup and restore provider.

The backend endpoint is `https://<public_domain>`. Cloud Tasks queue retries are bounded by its configured retry policy; monitor Cloud Logging and the queue's oldest task age / retry metrics. `../scalable-gcp` retains the older Cloud Run and Cloud SQL design and is not active.


## Repository layout

This repository owns the GCP Terraform root and its manual regional migration workflow. The application and Cloud Build deployment pipeline remain in [`chiefxai/chiefvoice`](https://github.com/chiefxai/chiefvoice); the application repository trusts this repository through the `github_infra_repository` Workload Identity Federation condition. Apply the Terraform change that adds this repository to the provider before using GitHub Actions here for the first time. Until that trust is applied, use an administrator workstation or Cloud Shell with Terraform and ADC to apply the updated configuration.
