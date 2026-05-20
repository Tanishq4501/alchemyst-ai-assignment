variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "subnet_id" {
  description = "Subnetwork ID to place the VM in (no external IP assigned)"
  type        = string
}

variable "name" {
  description = "VM name and Docker container name (e.g. caller-worker, inference-worker)"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-micro"
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "engine_ip" {
  description = "Internal IP of the iii engine VM (passed to worker as III_URL)"
  type        = string
}

variable "docker_image" {
  description = "Full Artifact Registry image URI (e.g. us-central1-docker.pkg.dev/project/alchemist/caller-worker:0.1.0)"
  type        = string
}
