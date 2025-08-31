# Provider and Resource
# Key Vault
# VM, Network and SubNets

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
  #  metadata_startup_script = <<-EOT
  #   #!/bin/bash
  #   sudo apt-get update -y
  #   sudo apt-get install -y openjdk-17-jdk wget gnupg git kubectl
  #   sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  #     https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
  #   echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  #     https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  #     /etc/apt/sources.list.d/jenkins.list > /dev/null
  #   sudo apt-get update -y
  #   sudo apt-get install jenkins
  # EOT
    metadata_startup_script = <<-EOT
      #!/bin/bash
      set -eux
      export DEBIAN_FRONTEND=noninteractive

      # Wait until dpkg/apt is free
      while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Another apt/dpkg process is running. Waiting..."
        sleep 10
      done

      # Base tools
      sudo apt-get update -y
      sudo apt-get install -y openjdk-17-jdk wget gnupg git apt-transport-https ca-certificates lsb-release curl

      # Install kubectl (latest stable)
      sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
      echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list
      sudo apt-get update -y
      sudo apt-get install -y kubectl

      # Jenkins repo key + list
      sudo mkdir -p /etc/apt/keyrings
      sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
      echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
        | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

      # Wait again in case another apt runs
      while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Waiting for apt lock before installing Jenkins..."
        sleep 10
      done

      # Install Jenkins
      sudo apt-get update -y
      sudo apt-get install -y jenkins

      # Enable + start Jenkins
      sudo systemctl daemon-reload
      sudo systemctl enable jenkins
      sudo systemctl start jenkins
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