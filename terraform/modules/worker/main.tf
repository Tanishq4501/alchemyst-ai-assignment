# Generic worker VM module — used for both caller-worker and inference-worker.
# The only differences between workers are: name, machine_type, disk_size, docker_image.

resource "google_compute_instance" "worker" {
  name         = var.name
  project      = var.project
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.disk_size
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    # No access_config = no external IP
  }

  metadata = {
    ENGINE_IP      = var.engine_ip
    DOCKER_IMAGE   = var.docker_image
    CONTAINER_NAME = var.name
  }

  metadata_startup_script = file("${path.module}/../../scripts/startup-worker.sh")

  service_account {
    scopes = ["cloud-platform"]
  }
}
