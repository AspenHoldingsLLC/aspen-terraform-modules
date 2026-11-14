output "backend" {
  description = "Settings for each layer's azurerm backend block. Add tenant_id, subscription_id, key and use_azuread_auth = true."
  value = {
    resource_group_name  = local.resource_group_name
    storage_account_name = azurerm_storage_account.this.name
    container_name       = azurerm_storage_container.this.name
  }
}

output "storage_account_id" {
  description = "Resource ID of the state account."
  value       = azurerm_storage_account.this.id
}
