variable "repository_name" {
  type        = string
  description = "The name of the Git repository holding the infrastructure code."
  default     = "workshop"
}

variable "repository_branch" {
  type        = string
  description = "The branch the stacks track."
  default     = "main"
}

variable "tf_version" {
  type        = string
  description = "The OpenTofu version the stacks use."
  default     = "1.10.3"
}

variable "vcs" {
  type = object({
    type       = string
    enterprise = optional(bool, false)
    namespace  = optional(string)
    id         = optional(string)
    url        = optional(string)
  })
  description = "VCS integration the stacks source their code from."

  # CHANGE ME: your VCS namespace and the ID of your own Spacelift VCS integration.
  # Note that enterprise = false targets github.com instead of GitHub Enterprise.
  default = {
    type       = "GITHUB"
    enterprise = true
    namespace  = "eminalemdar"
    id         = "github-enterprise-default-integration"
  }
}

variable "aws_integration_id" {
  type        = string
  description = "The ID of the Spacelift AWS integration the stacks assume for cloud credentials."

  # CHANGE ME: specific to the Spacelift account this was built in. Find yours
  # under Cloud integrations in the Spacelift UI.
  default = "01HCY7118NC0NWCZ0QTJKK8WB7"
}

variable "kubectl_version" {
  type        = string
  description = "The kubectl version the argocd stack uses. 'latest' takes the newest version Spacelift offers."
  default     = "latest"
}

variable "argocd_namespace" {
  type        = string
  description = "Namespace the argocd stack applies its manifests into. Must match argocd_namespace in aws/eks/variables.tf."
  default     = "argocd"
}
