variable "aws_region" {
  description = "AWS region for EKS cluster and networking"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile Terraform authenticates with (see ~/.aws/config)"
  type        = string
  default     = "default"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "bridge-the-gap-aws"
}
