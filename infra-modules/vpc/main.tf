# =============================================================================
# VPC with a public/private split across three availability zones.
#
# Layout per AZ:
#   public  ("utility" in kOps terminology) - NAT gateways, bastion,
#                                             internet-facing NLB/ALB
#   private                                 - control-plane and worker nodes
#
# Subnets carry the discovery tags that kOps and the AWS Load Balancer
# Controller need; getting these wrong is the single most common cause of
# "the controller silently refuses to provision a load balancer".
# =============================================================================

locals {
  # Tag every subnet as *shared* rather than *owned*. The VPC is created and
  # owned by Terraform, not by kOps, so kOps must not delete it on teardown.
  cluster_discovery_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  common_tags = merge(
    var.tags,
    {
      "Name"      = var.name
      "ManagedBy" = "terraform"
      "Module"    = "infra-modules/vpc"
    }
  )
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block = var.cidr_block

  # Both are required by kOps: nodes register in DNS by their internal hostname,
  # and the AWS cloud provider resolves them via the VPC resolver.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, local.cluster_discovery_tags, {
    Name = var.name
  })
}

# -----------------------------------------------------------------------------
# Internet gateway
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-igw"
  })
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # Nodes must never receive a public IP: the brief requires private topology.
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, local.cluster_discovery_tags, {
    Name = "${var.name}-private-${var.azs[count.index]}"
    Tier = "private"

    # Tells the AWS Load Balancer Controller this subnet may host *internal*
    # load balancers.
    "kubernetes.io/role/internal-elb" = "1"

    # Consumed by the kOps cluster template to place instance groups.
    "kops.k8s.io/subnet-type" = "Private"
  })
}

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # The bastion and NAT gateways need public addressing.
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, local.cluster_discovery_tags, {
    Name = "${var.name}-public-${var.azs[count.index]}"
    Tier = "public"

    # Tells the AWS Load Balancer Controller this subnet may host
    # *internet-facing* load balancers.
    "kubernetes.io/role/elb" = "1"

    "kops.k8s.io/subnet-type" = "Utility"
  })
}

# -----------------------------------------------------------------------------
# NAT gateways
#
# One per AZ up to nat_gateway_count. Private subnets in AZs beyond that count
# egress through the NAT gateway in the first AZ, which is the documented
# cost/resilience trade-off (see the nat_gateway_count variable description).
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = var.nat_gateway_count

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-eip-${var.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-${var.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------

# One shared public route table: every public subnet takes the same default
# route out through the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-rt-public"
    Tier = "public"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ, so each AZ can egress through its own NAT
# gateway and a NAT failure is contained to a single AZ.
resource "aws_route_table" "private" {
  count = length(var.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-rt-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

resource "aws_route" "private_default" {
  count = length(var.azs)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # AZs beyond nat_gateway_count fall back to the first NAT gateway.
  nat_gateway_id = aws_nat_gateway.this[
    min(count.index, var.nat_gateway_count - 1)
  ].id
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# S3 gateway endpoint
#
# kOps nodes read the cluster state store and the OIDC discovery documents from
# S3 on every boot. Routing that through the NAT gateway would be both slower
# and billed per GB; a gateway endpoint is free and keeps the traffic on the
# AWS backbone.
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private[*].id,
    [aws_route_table.public.id],
  )

  tags = merge(local.common_tags, {
    Name = "${var.name}-vpce-s3"
  })
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Flow logs (optional)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "${var.name}-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"

  tags = merge(local.common_tags, {
    Name = "${var.name}-flow-logs"
  })
}
