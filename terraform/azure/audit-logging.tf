# AKS control-plane audit logging.
#
# The `oms_agent` block on the cluster (see aks.tf) ships CONTAINER and node
# metrics/logs to Log Analytics. It does NOT ship control-plane audit logs.
# Those are a separate concern, delivered through an Azure Monitor diagnostic
# setting on the cluster resource itself. Verified empirically before adding
# this: `az monitor diagnostic-settings list --resource <aks-id>` returned an
# empty array, meaning no API server activity was being recorded anywhere.
#
# This matters because AKS here authenticates via local accounts, not Entra ID
# (see the Entra hardening item in the README). A static admin kubeconfig that
# cannot be revoked per-user, combined with no audit trail, means a compromise
# would be both unattributable and unrecorded. Enabling audit logging closes
# the second half of that pair.
#
# Category choice, deliberately not "everything":
#   kube-audit-admin - every MUTATING API call (create/update/delete/patch).
#                      This is the "who changed what" record. Excludes the
#                      very high volume read-only events that make full
#                      `kube-audit` expensive with little added signal here.
#   kube-apiserver   - API server operational log, needed to correlate
#                      authentication and admission failures with the audit
#                      events above.
#   guard            - Entra ID / RBAC authorisation decisions. Emits nothing
#                      today because Entra integration is not enabled, but is
#                      enabled here so the record appears automatically if it
#                      ever is, rather than being silently absent.
#
# Full `kube-audit` is intentionally not enabled: it duplicates
# kube-audit-admin plus all read traffic, and cost scales with cluster
# chatter rather than with security value at this size.
resource "azurerm_monitor_diagnostic_setting" "aks_control_plane" {
  name                       = "aks-control-plane-audit"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "guard"
  }
}
