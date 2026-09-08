output "zone_id" {
  description = "Hosted zone ID. external-dns is scoped to exactly this zone via its IRSA policy."
  value       = aws_route53_zone.this.zone_id
}

output "zone_arn" {
  description = "Hosted zone ARN, used to scope the external-dns IAM policy to this zone alone."
  value       = aws_route53_zone.this.arn
}

output "zone_name" {
  description = "Hosted zone name."
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Authoritative name servers. Empty in practice for private zones, where the VPC resolver answers instead."
  value       = aws_route53_zone.this.name_servers
}

output "is_private" {
  description = "Whether this zone is private."
  value       = var.private
}
