resource "azuread_application_registration" "github_actions" {
  display_name = "bridge-the-gap-github-actions-acr-push"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application_registration.github_actions.client_id
}

resource "azuread_application_federated_identity_credential" "github_actions" {
  application_id = azuread_application_registration.github_actions.id
  display_name   = "github-actions-main-branch"
  description    = "GitHub Actions OIDC, restricted to main branch of bridge-the-gap repo"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:VladvonTranssylvanien@105380245/bridge-the-gap@1317683530:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.object_id
}

output "github_actions_azure_client_id" {
  value = azuread_application_registration.github_actions.client_id
}

output "github_actions_azure_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

resource "azuread_application_federated_identity_credential" "github_actions_plan" {
  application_id = azuread_application_registration.github_actions.id
  display_name   = "github-actions-plan-any-ref"
  description    = "Read-only terraform plan, any branch/PR in this repo"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:VladvonTranssylvanien@105380245/bridge-the-gap@1317683530:pull_request"
}

resource "azurerm_role_assignment" "github_actions_plan_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.github_actions.object_id
}

