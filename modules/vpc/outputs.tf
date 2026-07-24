output "vpc_id" {
  value       = data.aws_vpc.default.id
  description = "VPC ID passed to the EKS module"
}

output "subnet_ids" {
  value       = data.aws_subnets.default.ids
  description = "Subnet IDs passed to the EKS cluster and node group"

  depends_on = [
    aws_ec2_tag.subnet_cluster,
    aws_ec2_tag.subnet_elb,
  ]
}
