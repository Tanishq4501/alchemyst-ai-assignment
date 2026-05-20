output "internal_ip" {
  description = "Internal IP of the worker VM"
  value       = google_compute_instance.worker.network_interface[0].network_ip
}

output "name" {
  value = google_compute_instance.worker.name
}
