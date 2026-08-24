output "region" {
  description = "AWS region the cluster was created in. Consumed by the argocd stack, which needs it to build a kubeconfig."
  value       = var.region
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "ID of the security group created for the cluster."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider used for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role used by EKS Auto Mode nodes."
  value       = module.eks.node_iam_role_arn
}

output "capabilities" {
  description = "ARN, version and IAM role of each EKS capability installed on the cluster."
  value = {
    ack = {
      arn          = module.ack.arn
      version      = module.ack.version
      iam_role_arn = module.ack.iam_role_arn
    }
    kro = {
      arn          = module.kro.arn
      version      = module.kro.version
      iam_role_arn = module.kro.iam_role_arn
    }
    argocd = {
      arn          = module.argocd.arn
      version      = module.argocd.version
      iam_role_arn = module.argocd.iam_role_arn
    }
  }
}

output "argocd_server_url" {
  description = "URL of the managed Argo CD server."
  value       = module.argocd.argocd_server_url
}

output "argocd_admin_group_id" {
  description = "ID of the IAM Identity Center group mapped to the Argo CD ADMIN role."
  value       = aws_identitystore_group.argocd_admins.group_id
}

output "argocd_admin_member_ids" {
  description = "IAM Identity Center user IDs that are members of the Argo CD admin group, keyed by user name."
  value       = { for name, user in data.aws_identitystore_user.argocd_admins : name => user.user_id }
}

output "configure_kubectl" {
  description = "Command to write a kubeconfig entry for the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
