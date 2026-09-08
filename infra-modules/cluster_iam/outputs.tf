# kOps expects spec.additionalPolicies to be a map of role name to a JSON
# *array of statements* - not a full policy document with Version/Statement.
# Emitting the wrong shape is rejected late, during `kops update`, with a
# confusing validation error, so the statement array is extracted here.

output "node_policy_json" {
  description = "Statement array for spec.additionalPolicies.node."
  value       = jsonencode(jsondecode(data.aws_iam_policy_document.node.json).Statement)
}

output "control_plane_policy_json" {
  description = "Statement array for spec.additionalPolicies.control-plane."
  value       = jsonencode(jsondecode(data.aws_iam_policy_document.control_plane.json).Statement)
}

output "node_policy_document" {
  description = "Full IAM policy document for the node role, for review and for attaching outside kOps."
  value       = data.aws_iam_policy_document.node.json
}

output "control_plane_policy_document" {
  description = "Full IAM policy document for the control-plane role."
  value       = data.aws_iam_policy_document.control_plane.json
}

output "additional_policies" {
  description = "Ready-to-render map for the kOps cluster spec's additionalPolicies block."
  value = {
    node            = jsonencode(jsondecode(data.aws_iam_policy_document.node.json).Statement)
    "control-plane" = jsonencode(jsondecode(data.aws_iam_policy_document.control_plane.json).Statement)
  }
}
