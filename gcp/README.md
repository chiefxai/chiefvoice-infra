# Chiefvoice GCP infrastructure

This repository owns the active GCP Terraform root at `gcp/`. The target environment is project `chiefvoice-service` (project number `577933119654`), region `asia-south1`, zone `asia-south1-a`. The application and Cloud Build deploy workflow remain in [`chiefxai/chiefvoice`](https://github.com/chiefxai/chiefvoice).

The deployment runs the API and PostgreSQL on a Compute Engine VM. Cloud Tasks queues post-call work for a second-generation Cloud Function. Cloud Storage holds recordings and encrypted backups. Terraform output values are the source of truth for the project, region, deployment service accounts, WIF provider resource name, and Cloud Build substitutions.

## Safety gates before initialization

The dedicated Terraform state bucket is `gs://chiefvoice-tfstate-577933119654-8db79b617764` in `ASIA-SOUTH1`, with uniform access, public access prevention, and versioning. The original candidate name was unavailable globally. The bucket was created through `gcp/state/`; preserve that root's local `terraform.tfstate` file in the Cloud Shell checkout. The main `gcp/` backend is initialized to this bucket with prefix `chiefvoice/prod`. Check its state addresses before importing any resources.

The target project already has a WIF pool `chiefvoice-service` and provider `github`, according to the current administrator report. The provider currently has an incorrect issuer and incomplete attribute mapping. Terraform now declares these exact resource IDs with the GitHub Actions issuer and restrictive repository/branch condition. Import the existing resources into the verified Terraform state before planning; do not create duplicate pools/providers or remove the existing resources.

The previously configured remote state could not be located in the projects visible to the administrator account. Existing WIF resources must be imported into the new main state before planning. Confirm the purpose of `gs://chiefvoice-service` before importing it as the recordings/backups bucket. Terraform manages the project-specific `${project_id}_cloudbuild` source bucket in the selected region; it is private and protected from destruction. Destruction is disabled for Terraform-managed state, object, and Cloud Build source buckets.

## 1. Authenticate and inspect existing state

Run these read-only commands in Cloud Shell or an administrator workstation. They do not modify project resources or Terraform state:

```sh
gcloud auth login
gcloud auth application-default login
gcloud config set project chiefvoice-service

gcloud projects describe chiefvoice-service \
  --format='yaml(projectId,projectNumber,name,lifecycleState)'
gcloud storage buckets describe gs://chiefvoice-tfstate-577933119654-8db79b617764 \
  --format='yaml(name,location,projectNumber,uniformBucketLevelAccess,publicAccessPrevention,versioning)'
gcloud storage ls gs://chiefvoice-tfstate-577933119654-8db79b617764/chiefvoice/prod/
gcloud storage buckets describe gs://chiefvoice-service \
  --format='yaml(name,location,projectNumber,uniformBucketLevelAccess,publicAccessPrevention,versioning)'
gcloud iam workload-identity-pools describe chiefvoice-service \
  --project=chiefvoice-service --location=global --format=yaml(name,state,disabled)
gcloud iam workload-identity-pools providers describe github \
  --project=chiefvoice-service --location=global \
  --workload-identity-pool=chiefvoice-service \
  --format='yaml(name,state,disabled,oidc,attributeMapping,attributeCondition)'
gcloud iam service-accounts list --project=chiefvoice-service --format='value(email)'
gcloud iam service-accounts get-iam-policy \
  chiefvoice-github-deploy@chiefvoice-service.iam.gserviceaccount.com \
  --project=chiefvoice-service --format=yaml(bindings)
gcloud projects get-iam-policy chiefvoice-service \
  --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:chiefvoice-github-deploy@chiefvoice-service.iam.gserviceaccount.com' \
  --format='table(bindings.role,bindings.members)'
```

Treat `PERMISSION_DENIED` as **unknown**, not as proof a bucket or state is absent. The original candidate state bucket was unavailable globally. The replacement bucket above has been created and verified in `chiefvoice-service`; use this exact name consistently in Terraform backend configuration, variables, and GitHub variables.

## 2. State bucket bootstrap and recovery

The separate `gcp/state/` Terraform root uses local state and creates only the protected state bucket and Cloud Storage API enablement. Both have already been created and are tracked in the current Cloud Shell checkout's `gcp/state/terraform.tfstate`. Preserve that file. On a fresh checkout, import the existing resources into local bootstrap state instead of applying an empty plan:

```sh
terraform -chdir=gcp/state init
terraform -chdir=gcp/state import \
  google_project_service.storage_api chiefvoice-service/storage.googleapis.com
terraform -chdir=gcp/state import \
  google_storage_bucket.terraform_state chiefvoice-tfstate-577933119654-8db79b617764
terraform -chdir=gcp/state state list
```

The bucket configuration enables uniform access, public access prevention, object versioning, `force_destroy = false`, and `prevent_destroy = true`. Do not run `terraform destroy` in this root. The main root grants the deployment service account state access only after that account exists.

## 3. Configure the main Terraform inputs and backend

After state ownership is resolved, create the local files from the examples and set the reviewed values. Keep `terraform.tfvars` and `backend.hcl` private and untracked:

```sh
cp gcp/backend.hcl.example gcp/backend.hcl
cp gcp/terraform.tfvars.example gcp/terraform.tfvars
```

The example targets `chiefvoice-service`, `asia-south1`, and the existing bucket `chiefvoice-service` for application objects. Verify that bucket’s purpose and import it if it is the bucket to retain. The example state bucket name is the verified replacement above. Configure `public_domain`, OIDC settings, trusted platform-admin subjects, VM size, and other required values before planning. The output sync rejects empty or malformed Cloud Build substitutions, so configure the OIDC substitution values before syncing deployment configuration.

Initialize the main backend using the created bucket and prefix `chiefvoice/prod`:

```sh
terraform -chdir=gcp init -backend-config=backend.hcl
terraform -chdir=gcp state list
```

The new remote state was initially empty. Import the verified live WIF resources and any existing buckets before planning. If another state object or unexpected addresses appear, stop and reconcile ownership before proceeding. Terraform state contains secret material, including generated credentials and secret versions; never print it, commit it, or share it.

If `gs://chiefvoice-service` is confirmed as the existing recordings/backups bucket and the main Terraform state does not already track `google_storage_bucket.objects`, import it rather than attempting to create a duplicate:

```sh
terraform -chdir=gcp import -var-file=terraform.tfvars \
  google_storage_bucket.objects chiefvoice-service
```

This changes Terraform state only. Do not run it if the bucket purpose/owner is uncertain or the resource address is already tracked.

## 4. Reconcile the existing WIF provider

The intended provider is in project `chiefvoice-service`, pool `chiefvoice-service`, provider `github`. Its issuer is `https://token.actions.githubusercontent.com`; mappings are `google.subject = assertion.sub`, `attribute.repository = assertion.repository`, and `attribute.ref = assertion.ref`. The condition permits only `chiefxai/chiefvoice` and `chiefxai/chiefvoice-infra` on `refs/heads/main`. The pool/provider IDs are immutable identifiers, so Terraform uses the reported existing IDs and protects both resources from accidental destruction.

After backend and state inspection, check whether these addresses already exist in state:

```sh
terraform -chdir=gcp state list | grep 'google_iam_workload_identity_pool'
```

If an address is absent and the live resource was verified, import it (these commands update Terraform state; they do not create/delete the GCP resource):

```sh
PROJECT_NUMBER="$(gcloud projects describe chiefvoice-service --format='value(projectNumber)')"
terraform -chdir=gcp import -var-file=terraform.tfvars \
  google_iam_workload_identity_pool.github \
  "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/chiefvoice-service"
terraform -chdir=gcp import -var-file=terraform.tfvars \
  google_iam_workload_identity_pool_provider.github \
  "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/chiefvoice-service/providers/github"
```

If either address is already tracked, do not import over it. Review `terraform state show` and the plan first. A project/state migration can require deliberate state moves/imports; any plan that destroys a pool, provider, service account, storage bucket, or data-bearing resource must be rejected until separately reviewed.

The WIF service-account impersonation binding is `roles/iam.workloadIdentityUser` for each repository principal in the pool. The current deploy service account has broad Terraform administration roles, including project IAM administration. Those privileges are powerful; review the plan and IAM set before approval and reduce them where the Terraform resource set permits. No service-account keys are needed.

## 5. Bootstrap using administrator ADC and review the plan

GitHub Actions cannot authenticate until the provider, service account, and impersonation binding exist. The first main-root apply therefore must be run by an administrator using ADC, after state has been verified and the existing WIF resources have been reconciled. This task has not run an apply.

```sh
terraform -chdir=gcp plan -var-file=terraform.tfvars
```

Review every action, especially replacements or deletions. The main root creates the deployment service account and WIF bindings. Apply only after the state and plan are confirmed and separately approved:

```sh
terraform -chdir=gcp apply -var-file=terraform.tfvars
```

Then retrieve the output values without printing secret data:

```sh
terraform -chdir=gcp output -raw project_id
terraform -chdir=gcp output -raw project_number
terraform -chdir=gcp output -raw region
terraform -chdir=gcp output -raw github_deploy_service_account
terraform -chdir=gcp output -raw github_workload_identity_provider
terraform -chdir=gcp output -raw cloud_build_service_account
```

The WIF output is generated from the actual project number and Terraform-managed pool/provider IDs; do not hardcode a project number or provider path in workflows.

## 6. Configure GitHub repositories

In `chiefxai/chiefvoice-infra`, configure repository Actions variables:

- `GCP_PROJECT_ID` = `chiefvoice-service`
- `GCP_REGION` = `asia-south1`
- `GCP_GITHUB_DEPLOY_SERVICE_ACCOUNT` = Terraform output `github_deploy_service_account`
- `GCP_WORKLOAD_IDENTITY_PROVIDER` = Terraform output `github_workload_identity_provider`
- `GCP_TF_STATE_BUCKET` = the verified state bucket name
- `GCP_TF_STATE_PREFIX` = `chiefvoice/prod`

Configure repository secrets `GCP_TERRAFORM_TFVARS` (the reviewed Terraform variables file) and `GCP_TF_PLAN_ENCRYPTION_KEY`. In the protected `production` environment, configure required reviewers and secret `CHIEFVOICE_REPO_VARIABLES_TOKEN`, a fine-grained token limited to `chiefxai/chiefvoice` with Actions Variables write permission. Never print or commit these secrets.

The sync workflow reads Terraform outputs and writes these six non-secret repository variables to `chiefxai/chiefvoice`: `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_GITHUB_DEPLOY_SERVICE_ACCOUNT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_CLOUD_BUILD_SERVICE_ACCOUNT`, and `GCP_CLOUDBUILD_SUBSTITUTIONS_JSON`. It validates all values before its first GitHub API write. It is restricted to the infrastructure repository’s `main` branch.

## 7. Plan, apply, and deploy

After the ADC bootstrap and GitHub variable setup, use `.github/workflows/terraform-apply-gcp.yml` from `main` for routine changes. Inspect the generated plan and approve only after reviewing all resource actions. The `terraform-gcp-region.yml` workflow is a separate data-discard migration workflow; it must not be used as a shortcut for project correction. The CI workflows never replace the need to inspect the plan.

Once infrastructure applies and output sync succeeds, verify that all six app repository variables are present without printing their values. Confirm DNS for the configured public domain points to the `backend_external_ip` output. Then run the `Deploy to GCP` workflow in `chiefxai/chiefvoice` on `main`. It authenticates through the synced WIF provider and Terraform-generated deployment service account, then submits the Cloud Build deployment.

The Cloud Build pipeline builds the API and React console images, deploys the post-call function, runs migrations, and exposes API/console on the configured HTTPS domain. Post-call transcript review uses Cloud Speech-to-Text Chirp 2 in `asia-southeast1`. The VM-only `deploy.sh` path does not deploy changes under `deploy/gcp/post-call-function/`; use Cloud Build for those changes.

For a manual VM connection after deployment:

```sh
gcloud compute ssh chiefvoice-backend \
  --project=chiefvoice-service --zone=asia-south1-a --tunnel-through-iap
```

## VM sizing

The Terraform example uses an `e2-standard-2` VM (2 vCPUs, 8 GB RAM) and a 50 GB boot disk. Set `vm_machine_type` and `vm_disk_gb` in the reviewed variables file, then inspect the protected workflow plan before applying.

## Backup and restore

The API takes service-scoped PostgreSQL backups with `pg_dump`, encrypts each archive, and stores it in the private object bucket. The VM service account has object access. Check a restore only into a disposable database using `sudo chiefvoice-backup-restore-check`; never restore over production data.

The GCS Terraform state includes generated secrets and rendered startup configuration. Protect its access and version history. The older `../scalable-gcp` Cloud Run/Cloud SQL design is not active.
