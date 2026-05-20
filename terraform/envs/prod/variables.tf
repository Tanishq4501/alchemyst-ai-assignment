variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "gateway_machine_type" {
  type    = string
  default = "e2-micro"
}

variable "worker_machine_type" {
  type    = string
  default = "e2-micro"
}

variable "inference_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "image_tag" {
  description = "Docker image tag to deploy (set by CI/CD to the git SHA)"
  type        = string
  default     = "latest"
}
