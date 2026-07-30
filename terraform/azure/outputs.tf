output "azure_subscription_id" {
  description = "Azure subscription ID Terraform is authenticated against"
  value       = data.azurerm_client_config.current.subscription_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID Terraform is authenticated against"
  value       = data.azurerm_client_config.current.tenant_id
}
