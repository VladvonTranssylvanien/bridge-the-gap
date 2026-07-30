variable "azure_subscription_id" {
  description = "Azure subscription ID (school account)"
  type        = string
  default     = "5249efa4-704e-4b43-b280-67250ffdfb57"
}

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  type        = string
  default     = "rg-bridge-the-gap"
}

variable "cluster_name" {
  description = "Name of the existing AKS cluster"
  type        = string
  default     = "bridge-the-gap-azure"
}

variable "istio_version" {
  description = "Istio version to install (chart + app version)"
  type        = string
  default     = "1.30.3"
}
