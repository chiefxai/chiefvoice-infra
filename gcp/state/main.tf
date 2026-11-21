terraform {
  required_version = ">= 1.8.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = "chief-502717"
  region  = "us-central1"
}

resource "google_project_service" "storage_api" {
  project            = "chief-502717"
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "terraform_state" {
  name                        = "chiefvoice-tfstate-297803100712"
  project                     = "chief-502717"
  location                    = "us-central1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.storage_api]
}
