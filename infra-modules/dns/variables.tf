variable "zone_name" {
  description = "Fully qualified zone name, e.g. \"corp.example.internal\"."
  type        = string
}

variable "private" {
  description = "Create a private hosted zone associated with var.vpc_associations. Set false to create a public zone (requires a registered, delegated domain)."
  type        = bool
  default     = true
}

variable "vpc_associations" {
  description = "VPCs to associate with a private zone. Required when private = true."
  type = list(object({
    vpc_id     = string
    vpc_region = string
  }))
  default = []
}

variable "comment" {
  description = "Zone comment shown in the Route53 console."
  type        = string
  default     = "Managed by Terraform - infra-modules/dns"
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the zone even when it still contains records created outside Terraform (external-dns writes into this zone)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the hosted zone."
  type        = map(string)
  default     = {}
}
