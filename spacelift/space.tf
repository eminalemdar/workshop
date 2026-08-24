resource "spacelift_space" "workshop" {
  name             = "workshop"
  description      = "Space for the workshop's networking, kubernetes and argocd stacks."
  parent_space_id  = "root"
  inherit_entities = true
}
