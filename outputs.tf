output "trustnote_jenkins_vm_ip" {
  value = google_compute_instance.trustnote_vm.network_interface[0].access_config[0].nat_ip
}

output "trustnote_gke_endpoint" {
  value = google_container_cluster.trustnote_gke.endpoint
}

output "secrets" {
  value = { 
    for key, secret in google_secret_manager_secret.trustnote_res : key => secret.id 
  }
}