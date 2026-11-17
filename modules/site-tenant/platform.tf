# The customer's own Container Apps environment and registry, when the caller doesn't pass shared ones.

# Consumption only (no workload profiles). Logs go to Azure Monitor and on to the caller's Log Analytics workspace
# through a diagnostic setting, which keeps the workspace's shared key out of state (the "log-analytics" destination
# needs it).
resource "azurerm_container_app_environment" "site" {
  count = local.own_environment ? 1 : 0

  name                = local.names.environment
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  logs_destination    = "azure-monitor"
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "environment" {
  count = local.own_environment && var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.names.environment}"
  target_resource_id         = azurerm_container_app_environment.site[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

# Basic, no admin user, no anonymous pull. ABAC mode, the same as a shared registry, so the role assignments in
# identity.tf work either way: each identity reaches only <key>/ repositories. AcrPull and AcrPush aren't honored in
# this mode.
resource "azurerm_container_registry" "site" {
  count = local.own_registry ? 1 : 0

  name                   = local.names.registry
  resource_group_name    = azurerm_resource_group.site.name
  location               = var.location
  sku                    = "Basic"
  admin_enabled          = false
  anonymous_pull_enabled = false
  role_assignment_mode   = "AbacRepositoryPermissions"
  tags                   = local.tags
}
