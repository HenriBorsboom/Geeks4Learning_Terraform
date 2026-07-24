variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "borsboomh"
}
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.small"
}
variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 1
}
variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 1
}
variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 2
}

locals {
  prefix       = var.prefix
  environment  = var.environment
  cluster_name = "${local.prefix}-eks-${local.environment}"
}

module "vpc" {
  source       = "./modules/vpc"
  prefix       = local.prefix
  environment  = local.environment
  cluster_name = local.cluster_name
}

module "eks" {
  source      = "./modules/eks"
  prefix      = local.prefix
  environment = local.environment
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.subnet_ids

  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
