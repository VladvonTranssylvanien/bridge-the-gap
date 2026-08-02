resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

resource "aws_eks_node_group" "main" {
  cluster_name           = aws_eks_cluster.main.name
  node_group_name_prefix = "${var.cluster_name}-ng-"
  node_role_arn          = aws_iam_role.eks_node.arn
  subnet_ids             = aws_subnet.private[*].id

  instance_types = ["m7i-flex.large"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy,
    aws_iam_role_policy_attachment.eks_node_ecr_policy,
  ]

  lifecycle {
    create_before_destroy = true
  }
}
