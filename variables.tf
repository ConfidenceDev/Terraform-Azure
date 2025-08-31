variable "gcp_svc_key" {
    description = "Project service account key"
}

variable "gcp_project" {
    description = "Project name"
}

variable "gcp_region" {
    description = "Project region"
}

variable "gcp_zone" {
    description = "Project zone"
}

variable "k8s_secrets" {
    default = {
        db_url   = "http://localhost:3711/db_trustnote"
        username = "test"
        password = "test@123"
    }
    description = "Database connection resources"  
}