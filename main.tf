###############################################################################
# Terraform configuration for Trustnote infrastructure on Google Cloud Platform
#
# Components:
# - Google Secret Manager: Creates secrets and secret versions for storing K8S environment variables.
# - Networking: Provisions a VPC network and firewall rules to allow SSH, HTTP, and Jenkins access.
# - Compute Instance: Deploys a VM with Debian 12, installs Jenkins, Git, and kubectl via startup script.
# - GKE Cluster: Creates an Autopilot Kubernetes cluster connected to the VPC.
#
# Resources:
# - google_secret_manager_secret: Manages secrets for K8S environment variables.
# - google_secret_manager_secret_version: Stores secret values for each secret.
# - google_compute_network: Creates a VPC network for all resources.
# - google_compute_firewall: Configures firewall rules for SSH (22), HTTP (80), and Jenkins (8080).
# - google_compute_instance: Provisions a VM and installs required software for CI/CD.
# - google_container_cluster: Deploys a GKE Autopilot cluster for Kubernetes workloads.
#
# Notes:
# - VM startup script installs Jenkins, Git, kubectl, and Java.
# - Firewall allows access from any IP address (0.0.0.0/0).
# - GKE cluster uses Autopilot mode for simplified management.
# - Node pool resource is commented out; Autopilot manages nodes automatically.
###############################################################################

# Secret Manager - To store all required K8S env ===================
resource "google_secret_manager_secret" "trustnote_res" {
    for_each = var.k8s_secrets
    
    # Use Key as Name in GCP
    secret_id = each.key
    replication {
      auto {}
    }
}

# Secret Manager - Entries
resource "google_secret_manager_secret_version" "trustnote_res_version" {
    for_each = var.k8s_secrets
    
    secret =  google_secret_manager_secret.trustnote_res[each.key].id
    secret_data = each.value
}

# Networking (VPC, Subnet and Firewall) - VM + GKE ===================
resource "google_compute_network" "trustnote_vpc" {
  name = "trustnote-vpc"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "trustnote_http_ssh" {
  name = "trustnote-http-ssh"
  network = google_compute_network.trustnote_vpc.name

# Ports - For SSH, HTTP and Jenkins
  allow {
    protocol = "tcp"
    ports = ["22", "80", "8080"]
  }

# Allow access form anywhere
  source_ranges = ["0.0.0.0/0"]
}

# VM Instance + Jenkins ===================
resource "google_compute_instance" "trustnote_vm" {
  name = "trustnote-vm"
  machine_type = "e2-micro" # 0.25 vCPU, 1 GB RAM
  zone = "${var.gcp_zone}"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12" #ubuntu-minimal-2404-lts-amd64
      size = 10 # Out of 250 GB quota
      type = "pd-ssd" #pd-standard
    }
  }

  network_interface {
    network = google_compute_network.trustnote_vpc.name
    access_config {} # Allocates an external public IP
  }

  # Install Jenkins, Git, and kubectl after VM creation
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    exec > >(tee /var/log/startup-script.log|logger -t startup-script) 2>&1

    export DEBIAN_FRONTEND=noninteractive

    # Initial update
    apt-get update -y
    apt-get install -y curl git apt-transport-https ca-certificates gnupg lsb-release

    # Install kubectl (correct repo for Debian 12)
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
      | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y kubectl

    # Install Java (required for Jenkins)
    apt-get install -y openjdk-17-jdk

    # Install Jenkins
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee \
      /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
      | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    apt-get update -y
    apt-get install -y jenkins

    # Start Jenkins
    systemctl enable jenkins
    systemctl start jenkins

    # Verify installations
    kubectl version --client || true
    jenkins --version || true
    
  EOT

}

# Setup GKE Cluster ===================
resource "google_container_cluster" "trustnote_gke" {
    name = "trustnote-gke"
    location = var.gcp_region

    # networking_mode = "VPC_NATIVE"
    # network = google_compute_network.trustnote_vpc.name

    # remove_default_node_pool = true
    # initial_node_count = 1
    enable_autopilot = true
    network          = google_compute_network.trustnote_vpc.name
    deletion_protection = false
}

# resource "google_container_node_pool" "trustnote_primary_nodes" {
#   name = "trustnote-default-pool"
#   cluster = google_container_cluster.trustnote_gke.name
#   location = var.gcp_region

# # Assigns each worker node size
#   node_config {
#     machine_type = "e2-micro" # 0.25 vCPU, 1 GB RAM
#     disk_size_gb = 10
#     disk_type = "pd-standard" # HDD - "pd-ssd"
#     oauth_scopes = [
#         "https://www.googleapis.com/auth/cloud-platform"
#     ]
#   }

# # Number of worker nodes
#   initial_node_count = 1
# }