# The shared training account has reached the 5-VPC regional limit.
# This module references the default VPC and its existing subnets instead of
# creating new ones. On a fresh AWS account with VPC headroom, replace the
# data sources below with the resource block at the bottom of this file.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "defaultForAz"
    values = ["true"]
  }
}

# Tag each default subnet so EKS can discover them for subnet assignment
# and the load balancer controller can place ELBs in them.
resource "aws_ec2_tag" "subnet_cluster" {
  for_each    = toset(data.aws_subnets.default.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "subnet_elb" {
  for_each    = toset(data.aws_subnets.default.ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

# -----------------------------------------------------------------------
# Full VPC creation — use these resources on a fresh account.
# Replace the data sources above with the blocks below and update
# outputs.tf to reference the resource names instead of the data sources.
# -----------------------------------------------------------------------
#
# resource "aws_vpc" "main" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_hostnames = true
#   enable_dns_support   = true
#
#   tags = {
#     Name        = "${var.prefix}-vpc-${var.environment}"
#     Environment = var.environment
#   }
# }
#
# resource "aws_subnet" "az1" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.1.0/24"
#   availability_zone       = "af-south-1a"
#   map_public_ip_on_launch = true
#   tags = {
#     Name                                        = "${var.prefix}-subnet-az1-${var.environment}"
#     Environment                                 = var.environment
#     "kubernetes.io/cluster/${var.cluster_name}" = "shared"
#     "kubernetes.io/role/elb"                    = "1"
#   }
# }
#
# resource "aws_subnet" "az2" { ... }
# resource "aws_subnet" "az3" { ... }
#
# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id
#   tags   = { Name = "${var.prefix}-igw-${var.environment}" }
# }
#
# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.main.id
#   route { cidr_block = "0.0.0.0/0"; gateway_id = aws_internet_gateway.main.id }
#   tags   = { Name = "${var.prefix}-rt-public-${var.environment}" }
# }
#
# resource "aws_route_table_association" "az1" { ... }
# resource "aws_route_table_association" "az2" { ... }
# resource "aws_route_table_association" "az3" { ... }
