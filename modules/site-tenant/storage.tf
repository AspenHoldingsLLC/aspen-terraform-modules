# Blob storage for one customer: portfolio images are public (anonymous read on that container only), the portal is
# private and served through short-lived user delegation links. Entra ID only: no account keys.

# Network access stays open: the public site loads portfolio images straight from it, and the apps reach it from
# Consumption-plan IPs that can't be allowlisted. Everything except the portfolio container needs Entra auth.
#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "site" {
  name                     = local.names.storage
  resource_group_name      = azurerm_resource_group.site.name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags

  # Holds the customer's photos. Removing a customer needs a deliberate step (README, "Removing a customer").
  lifecycle {
    prevent_destroy = true
  }
}

# Anonymous read on purpose: these images are on the public site.
#trivy:ignore:AZU-0007
resource "azurerm_storage_container" "portfolio" {
  name                  = "portfolio"
  storage_account_id    = azurerm_storage_account.site.id
  container_access_type = "blob"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "portal" {
  name                  = "portal"
  storage_account_id    = azurerm_storage_account.site.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# The client portal's access list: email => roles, bound to an account on first sign-in.
# One table per app, so a change on staging can never grant production access. Created through ARM, like the
# containers, because the account has no shared keys.
resource "azurerm_storage_table" "portal_access" {
  for_each = local.portal_access_tables

  name               = each.value
  storage_account_id = azurerm_storage_account.site.id

  # Holds who may see what. Removing it locks every buyer out (owners keep the External ID owner role).
  lifecycle {
    prevent_destroy = true
  }
}

# The build tracker: neighborhoods, plans and builds per builder. A build can name its
# buyer, so it lives here and never in git. One table per app, like the access list.
resource "azurerm_storage_table" "portal_builds" {
  for_each = local.portal_builds_tables

  name               = each.value
  storage_account_id = azurerm_storage_account.site.id

  lifecycle {
    prevent_destroy = true
  }
}
