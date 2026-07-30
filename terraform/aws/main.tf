# Smoke test: confirms the AWS provider can actually authenticate
# before we add real resources (VPC/EKS come in the next step).
data "aws_caller_identity" "current" {}
