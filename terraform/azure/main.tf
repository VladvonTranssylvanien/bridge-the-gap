# Smoke test: confirms the azurerm provider can actually authenticate
# before we add real resources (VNet/AKS come in the next step).
data "azurerm_client_config" "current" {}
