# Argo CD authenticates through IAM Identity Center; the admin group lives in the
# same identity store, so this is read even when the instance ARN is passed in.
data "aws_ssoadmin_instances" "this" {}

locals {
  argocd_idc_instance_arn = var.argocd_idc_instance_arn != "" ? var.argocd_idc_instance_arn : one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id       = var.argocd_idc_identity_store_id != "" ? var.argocd_idc_identity_store_id : one(data.aws_ssoadmin_instances.this.identity_store_ids)

  cluster_admin_access_entries = {
    for arn in var.cluster_admin_principal_arns : reverse(split("/", arn))[0] => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Never empty, so the capability always ships with an ADMIN mapping. Without
  # one, Argo CD authenticates the user but grants no role.
  argocd_admin_group_ids = concat(
    [aws_identitystore_group.argocd_admins.group_id],
    var.argocd_admin_sso_group_ids,
  )

  argocd_rbac_role_mapping = [{
    role = "ADMIN"
    identity = [for group_id in local.argocd_admin_group_ids : {
      id   = group_id
      type = "SSO_GROUP"
    }]
  }]
}

################################################################################
# Argo CD administrators — RBAC maps to IDC groups, so granting access is a
# membership change rather than an update to the capability.
################################################################################

resource "aws_identitystore_group" "argocd_admins" {
  identity_store_id = local.identity_store_id
  display_name      = var.argocd_admin_group_name
  description       = "Granted the Argo CD ADMIN role on the ${var.cluster_name} cluster."
}

data "aws_identitystore_user" "argocd_admins" {
  for_each = toset(var.argocd_admin_user_names)

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value
    }
  }
}

resource "aws_identitystore_group_membership" "argocd_admins" {
  for_each = data.aws_identitystore_user.argocd_admins

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.argocd_admins.group_id
  member_id         = each.value.user_id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access                   = var.endpoint_public_access
  enable_cluster_creator_admin_permissions = true

  # Auth is access-entry based (API mode); aws-auth ConfigMap is not used.
  access_entries = local.cluster_admin_access_entries

  # Auto Mode. Also brings managed EBS CSI and ALB/NLB, so there are no node
  # groups or core add-ons to declare.
  compute_config = {
    enabled    = true
    node_pools = var.node_pools
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  tags = var.tags
}

################################################################################
# EKS capabilities — AWS-managed platform components running outside the cluster
################################################################################

# AWS Controllers for Kubernetes: manage AWS resources through the Kubernetes API.
module "ack" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.24"

  type         = "ACK"
  cluster_name = module.eks.cluster_name

  iam_role_policies = var.ack_iam_role_policies

  tags = var.tags
}

# Kube Resource Orchestrator: compose resources into higher-level custom APIs.
# No IAM policies of its own — it only creates Kubernetes objects.
module "kro" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.24"

  type         = "KRO"
  cluster_name = module.eks.cluster_name

  tags = var.tags
}

# The capability's own AmazonEKSKROPolicy covers RGDs and instances but not the
# resources an RGD emits, so without this an instance creates nothing.
#
# Cluster admin is what AWS prescribes to get started. Scope it down for anything
# real: with the ACK capability's AdministratorAccess, anyone who can create a kro
# instance can create arbitrary AWS resources.
resource "aws_eks_access_policy_association" "kro" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.kro.iam_role_arn
  policy_arn    = var.kro_access_policy_arn

  access_scope {
    type = "cluster"
  }
}

# Argo CD's access entry is created with the capability but grants no Kubernetes
# RBAC, so without this it authenticates and then fails every deploy. Same
# trade-off as kro above: cluster admin to get started, narrow it for real use.
resource "aws_eks_access_policy_association" "argocd" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.argocd.iam_role_arn
  policy_arn    = var.argocd_access_policy_arn

  access_scope {
    type = "cluster"
  }
}

# Fully managed Argo CD for GitOps delivery into the cluster.
module "argocd" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.24"

  type         = "ARGOCD"
  cluster_name = module.eks.cluster_name

  configuration = {
    argo_cd = {
      aws_idc = {
        idc_instance_arn = local.argocd_idc_instance_arn
        idc_region       = var.region
      }
      namespace         = var.argocd_namespace
      rbac_role_mapping = local.argocd_rbac_role_mapping
    }
  }

  # Argo CD pulls manifests and images; ECR read access covers the common case.
  iam_policy_statements = {
    ECRRead = {
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
      ]
      resources = ["*"]
    }
  }

  tags = var.tags
}
