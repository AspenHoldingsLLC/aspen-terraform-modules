# One customer's website on Azure Container Apps: its own resource group, identities, a production app, a gated
# staging app, blob storage and the GitHub OIDC trust for its site repo.
#
# The Container Apps environment and the registry can be shared by several customers (pass their IDs) or belong to
# this customer alone (leave them null and the module creates them in the customer's resource group, platform.tf).

locals {
  rc = var.region_code

  names = {
    resource_group           = "rgp-${var.key}-${local.rc}"
    runtime_identity         = "uai-${var.key}-${local.rc}"
    staging_runtime_identity = "uai-${var.key}-staging-${local.rc}"
    deploy_prod              = "uai-${var.key}-ghprod-${local.rc}"
    deploy_staging           = "uai-${var.key}-ghstg-${local.rc}"
    production_app           = "cap-${var.key}-${local.rc}"
    staging_app              = "cap-${var.key}-staging-${local.rc}"
    storage                  = coalesce(var.storage_account_name, "sta${var.key}${local.rc}")
    staging_signin           = "app-${var.key}-staging"
    environment              = "cae-${var.key}-${local.rc}"
    registry                 = "acr${var.key}${local.rc}"
  }

  # The customer's repositories in the registry all sit under this prefix. The trailing slash matters: without it,
  # "abc" would also match "abcdef/...".
  acr_repository_prefix = "${var.key}/"

  tags = {
    environment = "prod"
    workload    = var.key
    owner       = var.owner
    managed-by  = "terraform"
  }

  own_environment = var.container_app_environment_id == null
  own_registry    = var.container_registry == null

  environment_id = local.own_environment ? azurerm_container_app_environment.site[0].id : var.container_app_environment_id
  environment = local.own_environment ? {
    default_domain    = azurerm_container_app_environment.site[0].default_domain
    static_ip_address = azurerm_container_app_environment.site[0].static_ip_address
    } : {
    default_domain    = data.azurerm_container_app_environment.shared[0].default_domain
    static_ip_address = data.azurerm_container_app_environment.shared[0].static_ip_address
  }

  registry = local.own_registry ? {
    id           = azurerm_container_registry.site[0].id
    login_server = azurerm_container_registry.site[0].login_server
  } : var.container_registry

  # Each app's address for the client portal's sign-in callback. The generated hostname unless the caller names one,
  # usually the custom domain.
  production_base_url = var.portal_sign_in == null ? null : coalesce(
    var.portal_sign_in.production_base_url, "https://${local.names.production_app}.${local.environment.default_domain}"
  )
  staging_base_url = var.portal_sign_in == null ? null : coalesce(
    var.portal_sign_in.staging_base_url, "https://${local.names.staging_app}.${local.environment.default_domain}"
  )
}

resource "azurerm_resource_group" "site" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

data "azurerm_container_app_environment" "shared" {
  count = local.own_environment ? 0 : 1

  name                = var.container_app_environment_name
  resource_group_name = split("/", var.container_app_environment_id)[4]
}
