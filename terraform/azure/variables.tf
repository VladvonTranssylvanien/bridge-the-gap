variable "azure_subscription_id" {
  description = "Azure subscription ID (school account)"
  type        = string
  default     = "5249efa4-704e-4b43-b280-67250ffdfb57"
}

variable "azure_location" {
  description = "Azure region for AKS cluster and networking"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Resource group name for this project"
  type        = string
  default     = "rg-bridge-the-gap"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "bridge-the-gap-azure"
}
