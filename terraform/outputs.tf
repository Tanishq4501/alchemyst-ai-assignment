output "api_gateway_public_ip" {
  description = "Public IP of the API gateway — use this in your curl commands"
  value       = google_compute_instance.api_gateway.network_interface[0].access_config[0].nat_ip
}

output "engine_internal_ip" {
  description = "Internal IP of the iii engine (api-gateway VM)"
  value       = google_compute_instance.api_gateway.network_interface[0].network_ip
}

output "caller_worker_internal_ip" {
  description = "Internal IP of the caller-worker VM"
  value       = google_compute_instance.caller_worker.network_interface[0].network_ip
}

output "inference_worker_internal_ip" {
  description = "Internal IP of the inference-worker VM"
  value       = google_compute_instance.inference_worker.network_interface[0].network_ip
}

output "api_endpoint" {
  description = "Full URL for the inference API"
  value       = "http://${google_compute_instance.api_gateway.network_interface[0].access_config[0].nat_ip}/v1/chat/completions"
}
