output "azure_subscription_id" {
  description = "Azure subscription ID Terraform is authenticated against"
  value       = data.azurerm_client_config.current.subscription_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID Terraform is authenticated against"
  value       = data.azurerm_client_config.current.tenant_id
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster (used by az aks get-credentials)"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_resource_group" {
  description = "Resource group containing the AKS cluster"
  value       = azurerm_resource_group.main.name
}
