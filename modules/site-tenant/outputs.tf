output "resource_group_name" {
  value = azurerm_resource_group.site.name
}

output "production_url" {
  value = "https://${azurerm_container_app.production.ingress[0].fqdn}"
}

output "staging_url" {
  value = "https://${azurerm_container_app.staging.ingress[0].fqdn}"
}

output "acr_repository_prefix" {
  description = "Push images under this prefix, e.g. <login server>/<key>/site:<sha>. Anything else is denied."
  value       = local.acr_repository_prefix
}

output "blob_endpoint" {
  value = azurerm_storage_account.site.primary_blob_endpoint
}

output "custom_domains" {
  description = "Hostnames bound to the production app."
  value       = keys(azurerm_container_app_custom_domain.production)
}

output "environment_static_ip" {
  description = "Apex domains point an A record here (shared by every customer in a shared environment)."
  value       = local.environment.static_ip_address
}

output "environment_default_domain" {
  description = "The environment's generated domain. Every app's hostname is <app>.<this>."
  value       = local.environment.default_domain
}

output "container_registry_login_server" {
  value = local.registry.login_server
}

output "custom_domain_verification_id" {
  description = "Value for the asuid TXT record when a domain is bound."
  value       = azurerm_container_app.production.custom_domain_verification_id
}

# The site repo's GitHub variables. None of these is secret.
output "github_variables" {
  value = {
    AZURE_TENANT_ID              = var.tenant_id
    AZURE_SUBSCRIPTION_ID        = split("/", azurerm_resource_group.site.id)[2]
    AZURE_CLIENT_ID_PRODUCTION   = azurerm_user_assigned_identity.deploy["prod"].client_id
    AZURE_CLIENT_ID_STAGING      = azurerm_user_assigned_identity.deploy["staging"].client_id
    ACR_LOGIN_SERVER             = local.registry.login_server
    ACR_REPOSITORY               = "${local.acr_repository_prefix}site"
    RESOURCE_GROUP               = azurerm_resource_group.site.name
    PRODUCTION_APP               = azurerm_container_app.production.name
    STAGING_APP                  = azurerm_container_app.staging.name
    STAGING_SIGNIN_APP_CLIENT_ID = azuread_application_registration.staging.client_id
  }
}

output "runtime_identity_principal_id" {
  description = "Production's runtime identity, for data roles granted outside the module."
  value       = azurerm_user_assigned_identity.runtime.principal_id
}

output "signup_gate_url" {
  description = "The sign-up gate's endpoint, for the External ID custom authentication extension. Null when the gate is off."
  value       = local.gate == 1 ? "https://${azurerm_function_app_flex_consumption.gate[0].default_hostname}/api/attributeCollectionStart" : null
}

output "signup_gate_app" {
  description = "The sign-up gate's function app name, for deploying its code. Null when the gate is off."
  value       = local.gate == 1 ? azurerm_function_app_flex_consumption.gate[0].name : null
}
