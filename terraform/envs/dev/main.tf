# Dev environment — same modules as prod, smaller machine types, separate state prefix.
module "network" {
  source      = "../../modules/network"
  project     = var.project_id
  region      = var.region
  vpc_name    = "alchemist-dev"
  subnet_cidr = "10.0.2.0/24"
}

module "engine" {
  source       = "../../modules/engine"
  project      = var.project_id
  region       = var.region
  zone         = var.zone
  subnet_id    = module.network.subnet_id
  machine_type = "e2-micro"
}

module "caller_worker" {
  source       = "../../modules/worker"
  project      = var.project_id
  zone         = var.zone
  subnet_id    = module.network.subnet_id
  name         = "caller-worker-dev"
  machine_type = "e2-micro"
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
  name         = "inference-worker-dev"
  machine_type = "e2-medium"
  disk_size    = 30
  engine_ip    = module.engine.internal_ip
  docker_image = "${module.engine.artifact_registry_url}/inference-worker:${var.image_tag}"

  depends_on = [module.network, module.engine]
}
