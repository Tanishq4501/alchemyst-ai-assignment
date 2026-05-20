variable "project_id" {
  description = "Your GCP project ID (e.g. my-project-123456)"
  type        = string
}

variable "region" {
  description = "GCP region to deploy into"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone to deploy into"
  type        = string
  default     = "us-central1-a"
}

variable "gateway_machine_type" {
  description = "Machine type for the API gateway VM (runs iii engine)"
  type        = string
  default     = "e2-micro"
}

variable "worker_machine_type" {
  description = "Machine type for the caller-worker VM (TypeScript)"
  type        = string
  default     = "e2-micro"
}

variable "inference_machine_type" {
  description = "Machine type for the inference-worker VM (Python + model). Needs at least 2 GB RAM."
  type        = string
  default     = "e2-medium"
}
