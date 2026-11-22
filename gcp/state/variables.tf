variable "project_id" {
  type    = string
  default = "chiefvoice-service"
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "terraform_state_bucket_name" {
  type        = string
  default     = "chiefvoice-tfstate-297803100712"
  description = "Candidate state bucket name; verify its existence, owner, and contents before bootstrap."
}
