output "internal_ip" {
  description = "Internal IP of the api-gateway VM (iii engine)"
  value       = google_compute_instance.api_gateway.network_interface[0].network_ip
}

output "external_ip" {
  description = "Public IP of the api-gateway VM"
  value       = google_compute_instance.api_gateway.network_interface[0].access_config[0].nat_ip
}

output "artifact_registry_url" {
  description = "Base URL for the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.workers.repository_id}"
}
