# A storage account for Terraform state, inside the subscription it describes.
#
# Access is Entra ID only: no account keys, no SAS, no anonymous reads. Blobs are versioned and soft-deleted, so an
# overwritten or deleted state file can be recovered.

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
}

# Public network access stays open so Terraform can run from GitHub-hosted runners and an operator's machine, neither
# of which has a fixed address to allow. The account takes Entra tokens only. Put it behind a private endpoint if
# applies move to a self-hosted runner.
#trivy:ignore:AZU-0012
resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = local.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.retention_days
    }

    container_delete_retention_policy {
      days = var.retention_days
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "data_contributor" {
  for_each = var.data_contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
