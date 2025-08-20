variable "gcp_svc_key" {}

variable "gcp_project" {}

variable "gcp_region" {}

variable "gcp_zone" {}

variable "k8s_secrets" {
    default = {
        db_url   = "http://localhost:3711/db_trustnote"
        username = "test"
        password = "test@123"
    }
    description = "Database connection resources"  
}