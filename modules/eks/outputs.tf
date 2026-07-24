output "cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name — use with aws eks update-kubeconfig"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "EKS API server endpoint"
}

output "cluster_ca_data" {
  value       = aws_eks_cluster.main.certificate_authority[0].data
  description = "Base64-encoded cluster CA certificate"
}
