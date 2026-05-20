output "api_gateway_public_ip" {
  value = module.engine.external_ip
}

output "api_endpoint" {
  value = "http://${module.engine.external_ip}/v1/chat/completions"
}

output "artifact_registry_url" {
  value = module.engine.artifact_registry_url
}

output "caller_worker_internal_ip" {
  value = module.caller_worker.internal_ip
}

output "inference_worker_internal_ip" {
  value = module.inference_worker.internal_ip
}
