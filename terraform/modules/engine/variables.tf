variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (used for Artifact Registry)"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "subnet_id" {
  description = "Subnetwork ID to place the VM in"
  type        = string
}

variable "machine_type" {
  description = "Machine type for the API gateway VM"
  type        = string
  default     = "e2-micro"
}
