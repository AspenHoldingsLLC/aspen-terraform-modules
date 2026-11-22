# The client portal's sign-up gate: an Azure Function that the External ID tenant calls before the sign-up form renders
# (a custom authentication extension on attributeCollectionStart). It lets an email continue only if it's on one of the
# portal access lists. The function's code lives in the site's own repo; this builds where it runs.
#
# Flex Consumption: it scales to zero and the free grant covers a site's sign-up volume. It has its own identity, which
# can read the access tables and nothing else of the customer's, and its own small storage account for the host and the
# deployment package, so the site's account isn't shared with function plumbing. No account keys anywhere.

locals {
  gate = var.portal_signup_gate != null && var.portal_sign_in != null ? 1 : 0

  gate_names = {
    identity = "uai-${var.key}-gate-${local.rc}"
    storage  = substr("stgate${var.key}${local.rc}", 0, 24)
    plan     = "asp-${var.key}-gate-${local.rc}"
    app      = "func-${var.key}-gate-${local.rc}"
    insights = "appi-${var.key}-gate-${local.rc}"
  }
}

resource "azurerm_user_assigned_identity" "gate" {
  count = local.gate

  name                = local.gate_names.identity
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  tags                = local.tags
}

# Host storage and the deployment package only. Public network access stays on because Flex Consumption without a
# virtual network reaches it over public endpoints; Entra auth is still required.
#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "gate" {
  count = local.gate

  name                     = local.gate_names.storage
  resource_group_name      = azurerm_resource_group.site.name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_container" "gate_deploy" {
  count = local.gate

  name                  = "deploy"
  storage_account_id    = azurerm_storage_account.gate[0].id
  container_access_type = "private"
}

# The Functions host keeps its locks and the deployment package in blobs.
resource "azurerm_role_assignment" "gate_host_storage" {
  count = local.gate

  scope                = azurerm_storage_account.gate[0].id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.gate[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Reads both access lists (staging testers sign up too). Read-only, on those tables only.
resource "azurerm_role_assignment" "gate_access_read" {
  for_each = local.gate == 1 ? azurerm_storage_table.portal_access : {}

  scope                = each.value.id
  role_definition_name = "Storage Table Data Reader"
  principal_id         = azurerm_user_assigned_identity.gate[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Logs and failures from the gate. Entra-only ingestion: the function writes with its identity, so the connection
# string alone can't be used to send data.
resource "azurerm_application_insights" "gate" {
  count = local.gate

  name                         = local.gate_names.insights
  resource_group_name          = azurerm_resource_group.site.name
  location                     = var.location
  application_type             = "Node.JS"
  workspace_id                 = var.portal_signup_gate.log_analytics_workspace_id
  local_authentication_enabled = false
  retention_in_days            = 30
  tags                         = local.tags
}

resource "azurerm_role_assignment" "gate_insights_publish" {
  count = local.gate

  scope                = azurerm_application_insights.gate[0].id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.gate[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_service_plan" "gate" {
  count = local.gate

  name                = local.gate_names.plan
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.tags
}

resource "azurerm_function_app_flex_consumption" "gate" {
  count = local.gate

  name                = local.gate_names.app
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.gate[0].id
  https_only          = true

  runtime_name    = "node"
  runtime_version = "22"

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.gate[0].primary_blob_endpoint}${azurerm_storage_container.gate_deploy[0].name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.gate[0].id

  # 40 is the lowest cap Flex Consumption accepts. Sign-ups are rare, so it's never reached in practice.
  maximum_instance_count = 40
  instance_memory_in_mb  = 512

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.gate[0].id]
  }

  app_settings = {
    AzureWebJobsStorage__accountName = azurerm_storage_account.gate[0].name
    AzureWebJobsStorage__credential  = "managedidentity"
    AzureWebJobsStorage__clientId    = azurerm_user_assigned_identity.gate[0].client_id
    AZURE_CLIENT_ID                  = azurerm_user_assigned_identity.gate[0].client_id
    GATE_TENANT_ID                   = var.portal_sign_in.tenant_id
    GATE_TENANT_SUBDOMAIN            = var.portal_signup_gate.tenant_subdomain
    GATE_AUDIENCES                   = join(",", var.portal_signup_gate.audiences)
    ACCESS_TABLE_ENDPOINT            = azurerm_storage_account.site.primary_table_endpoint
    ACCESS_TABLES                    = join(",", [for t in azurerm_storage_table.portal_access : t.name])
    # Entra auth for Application Insights ingestion, as the gate's identity.
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD;ClientId=${azurerm_user_assigned_identity.gate[0].client_id}"
  }

  site_config {
    minimum_tls_version                    = "1.2"
    application_insights_connection_string = azurerm_application_insights.gate[0].connection_string
  }

  tags = local.tags

  # Without the table role the gate answers 500 to every sign-up, so it waits for both roles.
  depends_on = [azurerm_role_assignment.gate_host_storage, azurerm_role_assignment.gate_access_read]
}
