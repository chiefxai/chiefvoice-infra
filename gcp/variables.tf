variable "project_id" { type = string }
variable "github_repository" {
  type        = string
  default     = "chiefxai/chiefvoice"
  description = "Application repository allowed to submit production Cloud Builds from its main branch."
}
variable "github_infra_repository" {
  type        = string
  default     = "chiefxai/chiefvoice-infra"
  description = "Infrastructure repository allowed to manage Terraform from its main branch using Workload Identity Federation."
}
variable "region" {
  type    = string
  default = "asia-south1"
}
variable "zone" {
  type    = string
  default = "asia-south1-a"
}
variable "vm_machine_type" {
  type    = string
  default = "e2-standard-2"
}
variable "vm_disk_gb" {
  type    = number
  default = 50
}
variable "terraform_state_bucket_name" {
  type        = string
  default     = "chiefvoice-tfstate-297803100712"
  description = "Candidate GCS state bucket; verify its project ownership and state before use."
}
variable "object_storage_bucket_name" { type = string }
variable "public_domain" {
  type        = string
  description = "DNS name pointed at the static backend_external_ip; Caddy manages HTTPS certificates."
}
variable "oidc_authority" {
  type        = string
  default     = ""
  description = "OIDC authority used by the console build, usually the issuer URL."
}
variable "oidc_client_id" {
  type        = string
  default     = ""
  description = "OIDC single-page application client ID used by the console build."
}
variable "oidc_scope" {
  type        = string
  default     = "openid profile email platform:customers:read platform:customers:write"
  description = "Space-separated OIDC scopes requested by the console."
}
variable "oidc_issuer" {
  type        = string
  default     = ""
  description = "Leave empty for infrastructure-only bootstrap; set before deploying the public console/API."
}
variable "oidc_audience" {
  type        = string
  default     = ""
  description = "Leave empty for infrastructure-only bootstrap; set before deploying the public console/API."
}
variable "oidc_jwks_url" {
  type        = string
  default     = ""
  description = "Leave empty for infrastructure-only bootstrap; set before deploying the public console/API."
}
variable "oidc_tenant_claim" {
  type        = string
  default     = "https://chiefvoice.elvoryx.in/tenant_id"
  description = "OIDC claim containing the platform tenant ID. Auth0 custom claims must be namespaced."
}
variable "platform_admin_subjects" {
  type        = list(string)
  default     = []
  description = "OIDC subject IDs allowed to provision and manage customer accounts."
}
variable "vertex_location" {
  type    = string
  default = "us-central1"
}
variable "vertex_model" {
  type    = string
  default = "google/gemini-live-2.5-flash-native-audio"
}
variable "post_call_model" {
  type    = string
  default = "gemini-3.5-flash-lite"
}
variable "post_call_location" {
  type    = string
  default = "global"
}
variable "post_call_transcription_location" {
  type        = string
  default     = "asia-southeast1"
  description = "Cloud Speech-to-Text region used for low-confidence post-call transcript review."
}
variable "post_call_transcription_model" {
  type        = string
  default     = "chirp_2"
  description = "Cloud Speech-to-Text model used for post-call transcript review."
}
variable "labels" {
  type    = map(string)
  default = { app = "chiefvoice", managed_by = "terraform" }
}
