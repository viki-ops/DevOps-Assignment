output "external_dns_role_arn" {
  description = "IRSA role ARN for external-dns."
  value       = module.external_dns.role_arn
}

output "cert_manager_role_arn" {
  description = "IRSA role ARN for cert-manager."
  value       = module.cert_manager.role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for cluster-autoscaler."
  value       = module.cluster_autoscaler.role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.aws_load_balancer_controller.role_arn
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for the External Secrets Operator."
  value       = module.external_secrets.role_arn
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI driver controller."
  value       = module.ebs_csi.role_arn
}

output "role_arns" {
  description = "All add-on IRSA role ARNs keyed by component. Consumed directly by the Ansible add-on bootstrap and by the Helm platform chart values."
  value = {
    external-dns                 = module.external_dns.role_arn
    cert-manager                 = module.cert_manager.role_arn
    cluster-autoscaler           = module.cluster_autoscaler.role_arn
    aws-load-balancer-controller = module.aws_load_balancer_controller.role_arn
    external-secrets             = module.external_secrets.role_arn
    ebs-csi-controller           = module.ebs_csi.role_arn
  }
}

output "policy_arns" {
  description = "Customer-managed policy ARNs created for the add-ons."
  value = {
    external-dns                 = module.external_dns.policy_arn
    cert-manager                 = module.cert_manager.policy_arn
    cluster-autoscaler           = module.cluster_autoscaler.policy_arn
    aws-load-balancer-controller = module.aws_load_balancer_controller.policy_arn
    external-secrets             = module.external_secrets.policy_arn
  }
}
