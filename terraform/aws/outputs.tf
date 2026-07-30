output "aws_account_id" {
  description = "AWS account ID Terraform is authenticated against"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_caller_arn" {
  description = "IAM identity Terraform is using"
  value       = data.aws_caller_identity.current.arn
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster (used by aws eks update-kubeconfig)"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}
