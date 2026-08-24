output "workshop_space_id" {
  value       = spacelift_space.workshop.id
  description = "The ID of the workshop space."
}

output "networking_stack_id" {
  value       = module.networking.id
  description = "The ID of the networking stack."
}

output "kubernetes_stack_id" {
  value       = module.kubernetes.id
  description = "The ID of the kubernetes stack."
}

output "argocd_stack_id" {
  value       = module.argocd.id
  description = "The ID of the argocd stack."
}
