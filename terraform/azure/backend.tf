# Remote state backend. Same reasoning as terraform/aws/backend.tf: local state
# was unencrypted, unlocked, single-generation and on one machine, while
# containing every computed attribute the provider returns - here that includes
# `kube_config_raw`, complete cluster administration for this AKS cluster in
# clear text (see hardening items 9 and 19 in the README).
#
# The storage account deliberately lives in a SEPARATE resource group,
# `rg-bridge-the-gap-tfstate`, not in `rg-bridge-the-gap`. Terraform manages that
# second resource group, so `terraform destroy` deletes everything inside it -
# which would include a storage account holding the very state file the destroy
# is reading from. Terraform would delete its own state mid-operation. Created
# manually, outside Terraform, for the same bootstrap reason as the S3 bucket.
#
# Storage account settings: TLS 1.2 minimum, public blob access disabled,
# encryption at rest with Microsoft-managed keys, and blob versioning enabled so
# a corrupted state can be rolled back to a previous version.
#
# `use_azuread_auth = true` authenticates to the blob with the caller's Entra
# identity via the Storage Blob Data Contributor role, rather than the storage
# account access key. The key would be a long-lived shared secret - exactly the
# thing this project exists to avoid - and it would end up in shell history and
# CI configuration. Note that Azure separates control plane from data plane:
# subscription Owner does not grant blob data access, the role assignment is
# required explicitly.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-bridge-the-gap-tfstate"
    storage_account_name = "stbtgtfstate8751b4"
    container_name       = "tfstate"
    key                  = "azure/terraform.tfstate"
    subscription_id      = "5249efa4-704e-4b43-b280-67250ffdfb57"
    tenant_id            = "c0531484-50fa-4ff2-97df-b1f2d4810603"
    use_azuread_auth     = true
  }
}
