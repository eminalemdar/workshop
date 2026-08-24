module "networking" {
  source = "github.com/spacelift-solutions/terraform-spacelift-stack?ref=v3.2.1"

  name        = "networking"
  description = "AWS networking (VPC, subnets, routing) for the workshop"

  space_id          = spacelift_space.workshop.id
  repository_name   = var.repository_name
  repository_branch = var.repository_branch
  project_root      = "aws/networking"
  vcs               = var.vcs

  workflow_tool = "OPEN_TOFU"
  tf_version    = var.tf_version
  auto_deploy   = true

  aws_integration = {
    enabled = true
    id      = var.aws_integration_id
  }

  labels = ["aws", "networking", "opentofu"]
}

module "kubernetes" {
  source = "github.com/spacelift-solutions/terraform-spacelift-stack?ref=v3.2.1"

  name        = "kubernetes"
  description = "AWS EKS cluster for the workshop"

  space_id          = spacelift_space.workshop.id
  repository_name   = var.repository_name
  repository_branch = var.repository_branch
  project_root      = "aws/eks"
  vcs               = var.vcs

  workflow_tool = "OPEN_TOFU"
  tf_version    = var.tf_version
  auto_deploy   = true

  aws_integration = {
    enabled = true
    id      = var.aws_integration_id
  }

  # Runs after networking, reading the VPC and subnet IDs from its outputs.
  # control_plane_subnet_ids is left unwired — the EKS module falls back to
  # subnet_ids when it is empty.
  dependencies = {
    networking = {
      parent_stack_id = module.networking.id

      references = {
        vpc_id = {
          input_name  = "TF_VAR_vpc_id"
          output_name = "vpc_id"
        }
        private_subnet_ids = {
          input_name  = "TF_VAR_private_subnet_ids"
          output_name = "private_subnets"
        }
      }
    }
  }

  labels = ["aws", "eks", "kubernetes", "opentofu"]
}

# Argo CD bootstrap manifests. Plain YAML rather than OpenTofu, so Spacelift
# applies them with kubectl.
module "argocd" {
  source = "github.com/spacelift-solutions/terraform-spacelift-stack?ref=v3.2.1"

  name        = "argocd"
  description = "Argo CD cluster/repository secrets and app-of-apps manifests for the workshop"

  space_id          = spacelift_space.workshop.id
  repository_name   = var.repository_name
  repository_branch = var.repository_branch
  project_root      = "kubernetes"
  vcs               = var.vcs

  workflow_tool = "KUBERNETES"
  auto_deploy   = true

  # A Terraform concept; kubectl's state is the cluster.
  manage_state = false

  kubernetes_config = {
    kubectl_version = var.kubectl_version

    # The one place the namespace is written down — the manifests carry none.
    namespace = var.argocd_namespace
  }

  aws_integration = {
    enabled = true
    id      = var.aws_integration_id
  }

  # Runs after the kubernetes stack, and takes the cluster to talk to from its
  # outputs. Applying that stack triggers this one.
  dependencies = {
    kubernetes = {
      parent_stack_id = module.kubernetes.id

      references = {
        cluster_name = {
          input_name  = "CLUSTER_NAME"
          output_name = "cluster_name"
        }
        region = {
          input_name  = "REGION_NAME"
          output_name = "region"
        }
        cluster_arn = {
          input_name  = "CLUSTER_ARN"
          output_name = "cluster_arn"
        }
      }
    }
  }

  environment_variables = {
    # Somewhere writable, rather than assuming HOME is.
    KUBECONFIG = { value = "/mnt/workspace/kubeconfig" }
  }

  # First line turns the AWS integration's credentials into a kubeconfig; that
  # role created the cluster, so it's already a cluster admin. Second fills in
  # the cluster ARN, which the managed Argo CD uses to identify clusters.
  hooks = {
    before = {
      init = [
        "aws eks update-kubeconfig --region $REGION_NAME --name $CLUSTER_NAME",
        "sed -i \"s|__CLUSTER_ARN__|$CLUSTER_ARN|g\" ./*.yaml",
      ]
    }
  }

  labels = ["aws", "argocd", "kubectl", "manifests"]
}
