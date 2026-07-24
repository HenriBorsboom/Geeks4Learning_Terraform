locals {
  cluster_name      = "${var.prefix}-eks-${var.environment}"
  cluster_role_name = "eks-cluster-${var.prefix}-role-${var.environment}"
  node_role_name    = "eks-node-${var.prefix}-role-${var.environment}"
  node_group_name   = "${var.prefix}-eks-ng-${var.environment}"
}

# Used to grant the deploying identity cluster-admin access automatically.
data "aws_caller_identity" "current" {}

# ----- Control Plane IAM -----

# The EKS control plane (the Kubernetes master) needs permission to call AWS
# APIs on your behalf — e.g. to create ENIs, describe EC2 instances, etc.
resource "aws_iam_role" "cluster" {
  name = local.cluster_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      # sts:TagSession is required when authentication_mode = "API" (EKS access entries).
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ----- EKS Control Plane -----

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  # API mode uses EKS access entries instead of the legacy aws-auth ConfigMap.
  # This is the modern, recommended authentication approach.
  access_config {
    authentication_mode = "API"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name        = local.cluster_name
    Environment = var.environment
  }
}

# ----- Access Entry -----

# Grant the IAM identity that runs terraform apply cluster-admin rights.
# Without this, you cannot run kubectl commands against the cluster after apply.
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"

  depends_on = [aws_eks_cluster.main]
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
