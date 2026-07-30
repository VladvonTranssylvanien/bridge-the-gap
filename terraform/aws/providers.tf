provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "bridge-the-gap"
      ManagedBy = "terraform"
    }
  }
}
