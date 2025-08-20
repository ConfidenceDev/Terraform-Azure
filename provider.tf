terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "6.48.0"
    }
  }
}

provider "google" {
  credentials = file(var.gcp_svc_key)
  project     = var.gcp_project
  region      = var.gcp_region
}
