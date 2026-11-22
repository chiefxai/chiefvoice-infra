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
  default     = "chiefvoice-tfstate-577933119654-8db79b617764"
  description = "Protected Terraform state bucket in chiefvoice-service."
}
