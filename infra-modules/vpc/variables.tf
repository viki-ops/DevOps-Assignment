variable "name" {
  description = "Name prefix for all resources, e.g. \"platform-dev\"."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. 10.20.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. Three are required for a HA control plane with an odd etcd quorum."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 3
    error_message = "Exactly three availability zones are required: etcd needs an odd quorum, and the brief mandates 3 AZs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets that carry control-plane and worker nodes. Must align 1:1 with azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 3
    error_message = "Provide exactly three private subnet CIDRs, one per AZ."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public (kOps calls them \"utility\") subnets that carry NAT gateways, the bastion and internet-facing load balancers. Must align 1:1 with azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 3
    error_message = "Provide exactly three public subnet CIDRs, one per AZ."
  }
}

variable "nat_gateway_count" {
  description = <<-EOT
    Number of NAT gateways to create, spread across the first N AZs.

    The brief requires at least 2. Set to 3 for full per-AZ isolation (no
    cross-AZ data charges and no shared failure domain); 2 is the documented
    cost/resilience compromise and is the default here.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.nat_gateway_count >= 2 && var.nat_gateway_count <= 3
    error_message = "nat_gateway_count must be 2 or 3: 1 would be a single point of egress failure, and there are only 3 AZs."
  }
}

variable "cluster_name" {
  description = "kOps cluster name, used to apply the kubernetes.io/cluster/<name> discovery tags that the AWS Load Balancer Controller and kOps rely on."
  type        = string
}

variable "enable_flow_logs" {
  description = "Emit VPC flow logs to CloudWatch. Off by default to avoid ongoing log ingestion cost in a short-lived environment."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for the VPC flow log group when enable_flow_logs is true."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
