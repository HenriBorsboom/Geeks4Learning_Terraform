variable "prefix" {
  type        = string
  description = "Naming prefix — format <surname><first_initial>, e.g. borsboomh"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod)"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — used to tag subnets so EKS can discover them"
}
