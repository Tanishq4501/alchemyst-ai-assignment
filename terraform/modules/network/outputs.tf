output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_id" {
  value = google_compute_subnetwork.private.id
}

output "subnet_cidr" {
  value = google_compute_subnetwork.private.ip_cidr_range
}
