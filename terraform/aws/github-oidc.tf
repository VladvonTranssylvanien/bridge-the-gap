resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = {
    Project   = "bridge-the-gap"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:VladvonTranssylvanien@105380245/bridge-the-gap@1317683530:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr_push" {
  name               = "bridge-the-gap-github-actions-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Project   = "bridge-the-gap"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [aws_ecr_repository.service_a.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions_ecr_push.id
  policy = data.aws_iam_policy_document.github_actions_ecr_push.json
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_ecr_push.arn
}

data "aws_iam_policy_document" "github_actions_plan_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      # Exact subjects instead of a ":*" wildcard. The plan workflow only ever
      # runs on two triggers (see .github/workflows/terraform-plan.yml):
      # pull_request, and workflow_dispatch from main. A wildcard would also
      # trust every other ref in the repo (any branch push, any tag), which
      # this role has no reason to accept.
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:VladvonTranssylvanien@105380245/bridge-the-gap@1317683530:pull_request",
        "repo:VladvonTranssylvanien@105380245/bridge-the-gap@1317683530:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_terraform_plan" {
  name               = "bridge-the-gap-github-actions-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_plan_assume_role.json

  tags = {
    Project   = "bridge-the-gap"
    ManagedBy = "terraform"
  }
}

# Least-privilege replacement for the AWS-managed ReadOnlyAccess policy.
#
# ReadOnlyAccess grants read on the entire account, including s3:GetObject,
# ssm:GetParameter (decrypting SecureString values) and dynamodb:GetItem.
# The plan workflow needs none of that. Because this project has no remote
# Terraform backend, `terraform plan` in CI starts from empty state: it does
# not read existing infrastructure, it plans creation of everything. The only
# AWS API calls it actually makes come from the two data sources that resolve
# at plan time:
#
#   data "aws_caller_identity"    -> sts:GetCallerIdentity
#   data "aws_availability_zones" -> ec2:DescribeAvailabilityZones
#
# Every `data "aws_iam_policy_document"` is rendered client-side by the
# provider and makes no API call. `data "tls_certificate" "eks_oidc"` depends
# on an EKS cluster attribute that is unknown with empty state, so it is
# deferred to apply and never runs during plan.
#
# Both actions below require resources = ["*"]: neither supports
# resource-level permissions in IAM.
#
# NOTE: if a remote backend (S3 + DynamoDB) is ever added, plan will start
# reading real infrastructure and this policy must be expanded to the
# Describe*/Get*/List* actions for every service in the configuration.
data "aws_iam_policy_document" "github_actions_plan_minimal" {
  statement {
    sid    = "TerraformPlanDataSources"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_terraform_plan_minimal" {
  name   = "terraform-plan-minimal"
  role   = aws_iam_role.github_actions_terraform_plan.id
  policy = data.aws_iam_policy_document.github_actions_plan_minimal.json
}

output "github_actions_terraform_plan_role_arn" {
  value = aws_iam_role.github_actions_terraform_plan.arn
}
