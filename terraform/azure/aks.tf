resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name

  # Restrict API server public access to a single admin IP. AKS automatically
  # allows the Standard LB's own outbound IP in addition to this list, so the
  # node pool cannot be locked out of its own control plane (confirmed against
  # Azure docs: api-server-authorized-ip-ranges.md).
  api_server_access_profile {
    authorized_ip_ranges = ["87.149.112.35/32"]
  }

  # Azure Policy add-on for AKS: enforces built-in Kubernetes-native
  # compliance/security policies (e.g. disallow privileged containers,
  # require read-only root filesystem) cluster-wide. Was previously
  # disabled entirely. Single boolean, no node pool disruption.
  azure_policy_enabled = true

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = azurerm_subnet.aks.id

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Project   = "bridge-the-gap"
    ManagedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [tags["created-on"]]
  }
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  # Something outside Terraform (likely AKS's Container Insights linkage,
  # not an Azure Policy - none exists on this subscription, confirmed)
  # keeps re-stamping a "created-on" tag on this workspace. Without this,
  # every `terraform apply` shows a perpetual, harmless diff trying to
  # remove it. Scoped to only this one tag key so any other real tag
  # drift on this resource still surfaces normally.
  lifecycle {
    ignore_changes = [tags["created-on"]]
  }
}
