provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "bridge-the-gap"
      ManagedBy = "terraform"
    }
  }
}
