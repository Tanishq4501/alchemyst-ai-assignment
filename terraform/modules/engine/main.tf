resource "google_artifact_registry_repository" "workers" {
  project       = var.project
  location      = var.region
  repository_id = "alchemist"
  format        = "DOCKER"
  description   = "Docker images for iii workers"
}

resource "google_compute_instance" "api_gateway" {
  name         = "api-gateway"
  project      = var.project
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["api-gateway"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    access_config {}
  }

  metadata_startup_script = file("${path.module}/../../scripts/startup-engine.sh")

  service_account {
    scopes = ["cloud-platform"]
  }
}
