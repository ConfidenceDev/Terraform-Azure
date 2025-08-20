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
      image = "debian-cloud/debian-12"
      size = 10 # Out of 250 GB quota
      type = "pd-standard"
    }
  }

  network_interface {
    network = google_compute_network.trustnote_vpc.name
    access_config {} # Allocates an external public IP
  }

# Install and Start Jenkins after VM creation
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y openjdk-17-jdk wget gnupg
    wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | tee \
      /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
      https://pkg.jenkins.io/debian-stable binary/ | tee \
      /etc/apt/sources.list.d/jenkins.list > /dev/null
    apt-get update -y
    apt-get install -y jenkins
    systemctl enable jenkins
    systemctl start jenkins
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