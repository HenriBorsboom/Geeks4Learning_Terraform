output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID — passed to the EKS module"
}

output "subnet_ids" {
  value       = [aws_subnet.az1.id, aws_subnet.az2.id, aws_subnet.az3.id]
  description = "List of all subnet IDs — passed to the EKS cluster and node group"
}
