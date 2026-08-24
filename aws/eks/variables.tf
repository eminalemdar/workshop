variable "region" {
  type        = string
  description = "AWS region the EKS cluster is created in."
  default     = "eu-west-1"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Must match the cluster_name used by the networking stack so the subnet discovery tags line up."
  default     = "workshop"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes <major>.<minor> version of the control plane. 1.36 is the newest version available on Amazon EKS."
  default     = "1.36"
}

variable "node_pools" {
  type        = list(string)
  description = "EKS Auto Mode built-in node pools to enable. 'system' hosts critical add-ons, 'general-purpose' hosts workloads."
  default     = ["system", "general-purpose"]
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the Kubernetes API server endpoint publicly. Needed to reach the cluster from outside the VPC."
  default     = true
}

variable "cluster_admin_principal_arns" {
  type        = list(string)
  description = "IAM principal ARNs granted cluster-wide admin through an EKS access entry. The stack is applied by the Spacelift AWS integration role, so enable_cluster_creator_admin_permissions only covers that role — human users need to be listed here to reach the cluster with kubectl."

  # CHANGE ME: points at the AWS account this workshop was built in. Replace with
  # your own principals or you will not be able to reach the cluster.
  default = ["arn:aws:iam::247747705325:user/emin"]
}

################################################################################
# Networking references — empty by default, injected as TF_VAR_<name> from the
# networking stack's outputs.
################################################################################

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the cluster is deployed into. Set via TF_VAR_vpc_id."
  default     = ""
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of the private subnets Auto Mode places nodes in. Set via TF_VAR_private_subnet_ids, e.g. '[\"subnet-a\",\"subnet-b\"]'."
  default     = []
}

variable "control_plane_subnet_ids" {
  type        = list(string)
  description = "IDs of the subnets the control plane ENIs are placed in. Falls back to private_subnet_ids when empty. Set via TF_VAR_control_plane_subnet_ids."
  default     = []
}

################################################################################
# EKS capabilities
################################################################################

variable "ack_iam_role_policies" {
  type        = map(string)
  description = "IAM policies attached to the ACK capability role, in {name = policy_arn} format. AdministratorAccess is what the upstream example uses and is fine for a workshop — scope it down to the AWS services ACK actually manages for anything real."
  default = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
  }
}

variable "kro_access_policy_arn" {
  type        = string
  description = "EKS access policy associated with the kro capability role so it can manage the resources its ResourceGraphDefinitions create. AmazonEKSClusterAdminPolicy is what AWS recommends for getting started and covers any RGD — swap it for a narrower policy, or replace this association with custom RBAC, for anything beyond a workshop."
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

variable "argocd_access_policy_arn" {
  type        = string
  description = "EKS access policy associated with the Argo CD capability role so it can deploy into this cluster. AmazonEKSClusterAdminPolicy is what AWS recommends for getting started; scope it down for anything beyond a workshop."
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

variable "argocd_namespace" {
  type        = string
  description = "Namespace the managed Argo CD capability is installed into."
  default     = "argocd"
}

variable "argocd_idc_instance_arn" {
  type        = string
  description = "ARN of the IAM Identity Center instance Argo CD authenticates against. Discovered from the account when empty. Set via TF_VAR_argocd_idc_instance_arn."
  default     = ""
}

variable "argocd_idc_identity_store_id" {
  type        = string
  description = "ID of the IAM Identity Center identity store the Argo CD admin group is created in. Discovered from the IDC instance when empty. Set via TF_VAR_argocd_idc_identity_store_id."
  default     = ""
}

variable "argocd_admin_group_name" {
  type        = string
  description = "Display name of the IAM Identity Center group created for Argo CD administrators."
  default     = "argocd-admins"
}

variable "argocd_admin_user_names" {
  type        = list(string)
  description = "IAM Identity Center user names added to the Argo CD admin group. These must already exist in the identity store — the workshop does not provision users. Add a workshop attendee here to give them the Argo CD ADMIN role."

  # CHANGE ME: an Identity Center user from the account this was built in. With no
  # valid member here nobody can get into the Argo CD UI.
  default = ["eminalemdar"]
}

variable "argocd_admin_sso_group_ids" {
  type        = list(string)
  description = "Pre-existing IAM Identity Center group IDs granted the Argo CD ADMIN role, in addition to the group created by this stack. Optional."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default = {
    Project   = "workshop"
    ManagedBy = "spacelift"
  }
}
