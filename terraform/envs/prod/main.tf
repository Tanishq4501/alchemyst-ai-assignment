# Import the Artifact Registry repo that was pre-created manually.
# Terraform 1.5+ import blocks are idempotent — no-op if already in state.
import {
  to = module.engine.google_artifact_registry_repository.workers
  id = "projects/${var.project_id}/locations/us-central1/repositories/alchemist"
}

module "network" {
  source      = "../../modules/network"
  project     = var.project_id
  region      = var.region
  vpc_name    = "alchemist"
  subnet_cidr = "10.0.1.0/24"
}

module "engine" {
  source       = "../../modules/engine"
  project      = var.project_id
  region       = var.region
  zone         = var.zone
  subnet_id    = module.network.subnet_id
  machine_type = var.gateway_machine_type
}

module "caller_worker" {
  source       = "../../modules/worker"
  project      = var.project_id
  zone         = var.zone
  subnet_id    = module.network.subnet_id
  name         = "caller-worker"
  machine_type = var.worker_machine_type
  disk_size    = 20
  engine_ip    = module.engine.internal_ip
  docker_image = "${module.engine.artifact_registry_url}/caller-worker:${var.image_tag}"

  depends_on = [module.network, module.engine]
}

module "inference_worker" {
  source       = "../../modules/worker"
  project      = var.project_id
  zone         = var.zone
  subnet_id    = module.network.subnet_id
  name         = "inference-worker"
  machine_type = var.inference_machine_type
  disk_size    = 30
  engine_ip    = module.engine.internal_ip
  docker_image = "${module.engine.artifact_registry_url}/inference-worker:${var.image_tag}"

  depends_on = [module.network, module.engine]
}
