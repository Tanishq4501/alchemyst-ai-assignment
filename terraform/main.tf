terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "alchemist-tf-state"
    prefix = "envs/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── VPC & Networking ────────────────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = "alchemist-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private" {
  name          = "alchemist-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Cloud Router — required for NAT
resource "google_compute_router" "router" {
  name    = "alchemist-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT — lets private VMs reach the internet (for apt, pip, npm, HuggingFace)
resource "google_compute_router_nat" "nat" {
  name                               = "alchemist-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ─── Firewall Rules ───────────────────────────────────────────────────────────

# Allow HTTP on port 80 from the public internet — only to the api-gateway VM
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["api-gateway"]
}

# Allow SSH via Identity-Aware Proxy (no public SSH exposure)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# Allow all traffic within the private subnet (RPC WebSocket, internal HTTP)
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.1.0/24"]
}

# ─── VM: API Gateway (engine host, public-facing) ────────────────────────────

resource "google_compute_instance" "api_gateway" {
  name         = "api-gateway"
  machine_type = var.gateway_machine_type
  zone         = var.zone
  tags         = ["api-gateway"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    access_config {}  # assigns a public IP
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-engine.sh")

  service_account {
    scopes = ["cloud-platform"]
  }
}

# ─── VM: Caller Worker (TypeScript, private) ──────────────────────────────────

resource "google_compute_instance" "caller_worker" {
  name         = "caller-worker"
  machine_type = var.worker_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config block = no external IP
  }

  metadata = {
    ENGINE_IP = google_compute_instance.api_gateway.network_interface[0].network_ip
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-caller.sh")

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [google_compute_router_nat.nat, google_compute_instance.api_gateway]
}

# ─── VM: Inference Worker (Python + model, private) ──────────────────────────

resource "google_compute_instance" "inference_worker" {
  name         = "inference-worker"
  machine_type = var.inference_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30  # extra space for GGUF model weights (~300 MB)
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config block = no external IP
  }

  metadata = {
    ENGINE_IP = google_compute_instance.api_gateway.network_interface[0].network_ip
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-inference.sh")

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [google_compute_router_nat.nat, google_compute_instance.api_gateway]
}
