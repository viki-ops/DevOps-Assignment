output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC. Used to scope security group rules and the kOps kubernetesApiAccess allow-list."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs, ordered to match var.azs."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public (utility) subnet IDs, ordered to match var.azs."
  value       = aws_subnet.public[*].id
}

output "private_subnets_by_az" {
  description = "Map of AZ name to private subnet ID. The kOps cluster template consumes this directly to pin each instance group to a subnet."
  value       = { for i, az in var.azs : az => aws_subnet.private[i].id }
}

output "public_subnets_by_az" {
  description = "Map of AZ name to public (utility) subnet ID."
  value       = { for i, az in var.azs : az => aws_subnet.public[i].id }
}

output "private_subnet_cidrs_by_az" {
  description = "Map of AZ name to private subnet CIDR."
  value       = { for i, az in var.azs : az => aws_subnet.private[i].cidr_block }
}

output "public_subnet_cidrs_by_az" {
  description = "Map of AZ name to public subnet CIDR."
  value       = { for i, az in var.azs : az => aws_subnet.public[i].cidr_block }
}

output "azs" {
  description = "Availability zones this VPC spans."
  value       = var.azs
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_by_az" {
  description = <<-EOT
    Map of AZ to the NAT gateway that AZ egresses through. AZs beyond
    nat_gateway_count share the last gateway, mirroring the route table logic
    exactly.

    kOps consumes this as `spec.subnets[].egress`. Omitting it would cause kOps
    to provision its own NAT gateways inside our shared VPC, duplicating cost
    and leaving resources Terraform does not track.
  EOT
  value = {
    for i, az in var.azs :
    az => aws_nat_gateway.this[min(i, var.nat_gateway_count - 1)].id
  }
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways. These are the cluster's stable egress addresses - useful for allow-listing at third parties."
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "Internet gateway ID."
  value       = aws_internet_gateway.this.id
}

output "private_route_table_ids" {
  description = "Private route table IDs, one per AZ."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "The shared public route table ID."
  value       = aws_route_table.public.id
}
