output "repo_server_role_arn" {
  description = "IRSA role ARN for the ArgoCD repo-server and application-controller."
  value       = module.repo_server.role_arn
}

output "repo_server_role_name" {
  description = "Name of the ArgoCD IRSA role."
  value       = module.repo_server.role_name
}

output "policy_arn" {
  description = "ARN of the managed policy attached to the ArgoCD role."
  value       = module.repo_server.policy_arn
}

output "service_account_annotations" {
  description = "Annotations to apply to the ArgoCD ServiceAccounts, ready for Helm values."
  value = {
    "argocd-repo-server"            = module.repo_server.service_account_annotation
    "argocd-application-controller" = module.repo_server.service_account_annotation
  }
}
