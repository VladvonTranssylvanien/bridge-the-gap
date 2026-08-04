# Remote state backend.
#
# Before this, state lived in a local `terraform.tfstate` file: unencrypted,
# on one laptop, with a single generation of backup and no locking. That file
# contains every attribute of every managed resource, including computed
# sensitive ones the provider returns automatically - there is no way to tell
# Terraform to manage a resource but not record an attribute. `sensitive = true`
# only hides values from CLI output; state still holds them in clear text.
#
# The bucket is created manually, outside Terraform, on purpose: a bucket that
# holds the state of a configuration cannot be managed by that same
# configuration. It has versioning (recover a corrupted state), SSE-S3
# encryption at rest, all public access blocked, and a bucket policy that denies
# any request not made over TLS.
#
# `use_lockfile = true` uses S3-native conditional writes for state locking
# (Terraform 1.10+), so no separate DynamoDB table is needed. Without locking,
# two concurrent applies silently corrupt state.
#
# A customer-managed KMS key instead of SSE-S3 would add key-usage audit trail
# via CloudTrail and independent key rotation control. Not done here: SSE-S3
# already encrypts at rest, and a CMK adds a hard failure mode - if the key is
# disabled or deleted, the state becomes permanently unreadable.
terraform {
  backend "s3" {
    bucket       = "bridge-the-gap-tfstate-628409561582"
    key          = "aws/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
