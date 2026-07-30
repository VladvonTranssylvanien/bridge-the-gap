provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

data "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}
