variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vm_ami_id" {
  type        = string
  description = "Ubuntu 24.04 LTS AMI in the selected region."
}
variable "vm_instance_type" {
  type = string
  default = "t3.large"
}
variable "vm_disk_gb" {
  type = number
  default = 100
}
variable "ssh_allowed_cidr" {
  type        = string
  description = "Admin IP CIDR; use a narrow range."
}
variable "ssh_key_name" {
  type = string
  default = null
}
variable "api_image_uri" {
  type        = string
  description = "Chiefvoice API image URI."
}
variable "public_domain" {
  type        = string
  description = "DNS name pointed at the output backend_public_ip; Caddy obtains and renews TLS certificates."
}
variable "oidc_issuer" { type = string }
variable "oidc_audience" { type = string }
variable "oidc_jwks_url" { type = string }
variable "platform_admin_subjects" {
  type        = list(string)
  default     = []
  description = "OIDC subject IDs allowed to provision and manage customer accounts."
}
variable "vertex_location" {
  type = string
  default = "us-central1"
}
variable "vertex_model" {
  type = string
  default = "google/gemini-live-2.5-flash-native-audio"
}
variable "post_call_model" {
  type = string
  default = "gemini-3.5-flash-lite"
}
variable "post_call_location" {
  type = string
  default = "global"
}
variable "gcp_project_parent" { type = string }
variable "gcp_billing_account_id" { type = string }
variable "gcp_runtime_service_account" { type = string }
variable "gcp_budget_api_project_id" { type = string }
variable "gcp_vertex_monthly_spend_cap" {
  type = string
  default = "100"
}
variable "google_credentials_secret_arn" {
  type        = string
  description = "AWS Secrets Manager ARN of the service-account JSON authorized to provision tenant Vertex projects and call Vertex."
}
variable "recordings_enabled" {
  type = bool
  default = false
}
variable "post_call_lambda_image_uri" {
  type        = string
  description = "ARM64 Lambda image URI."
}
variable "object_storage_bucket_name" { type = string }
variable "database_name" {
  type = string
  default = "chiefvoice"
}
variable "database_username" {
  type = string
  default = "chiefvoice"
}
variable "tags" {
  type    = map(string)
  default = { Application = "chiefvoice", ManagedBy = "terraform" }
}
