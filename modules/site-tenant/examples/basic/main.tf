# Placeholder IDs only. A real landing zone pins exact versions and its own tenant and subscription.
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.10, < 6.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.13, < 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.9, < 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  tenant_id           = "00000000-0000-0000-0000-000000000000"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  storage_use_azuread = true

  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.ContainerRegistry",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]
}

provider "azapi" {
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

provider "azuread" {
  tenant_id = "00000000-0000-0000-0000-000000000000"
}

# The customer's own environment and registry, with the client portal and the AI editor switched on.
module "site" {
  source = "../.."

  key         = "example"
  location    = "eastus2"
  region_code = "eus2"
  owner       = "Example Ltd"
  tenant_id   = "00000000-0000-0000-0000-000000000000"

  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rgp-mgmt-eus2/providers/Microsoft.OperationalInsights/workspaces/law-mgmt-eus2"

  github_subject_prefix = "repo:ExampleOrg@1111111/example-site@2222222"

  portal_sign_in = {
    tenant_id                   = "33333333-3333-3333-3333-333333333333"
    client_id                   = "44444444-4444-4444-4444-444444444444"
    key_vault_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rgp-sharedsvc-eus2/providers/Microsoft.KeyVault/vaults/kvt-example-eus2"
    key_vault_uri               = "https://kvt-example-eus2.vault.azure.net/"
    client_secret_name          = "PORTAL-CLIENT-SECRET"
    session_secret_name         = "PORTAL-SESSION-SECRET"
    staging_session_secret_name = "PORTAL-STAGING-SESSION-SECRET"
    production_base_url         = "https://www.example.com"
  }

  editor = {
    github_repo       = "ExampleOrg/example-site"
    users             = ["editor@example.com"]
    key_vault_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rgp-sharedsvc-eus2/providers/Microsoft.KeyVault/vaults/kvt-example-eus2"
    key_vault_uri     = "https://kvt-example-eus2.vault.azure.net/"
    token_secret_name = "EDITOR-GITHUB-TOKEN"
  }

  operator_object_ids     = ["55555555-5555-5555-5555-555555555555"]
  staging_user_object_ids = {}

  target_port = 3000

  custom_domains = {
    "www.example.com" = { certificate_name = "mc-www-example-com", validation = "TXT" }
  }
}

output "github_variables" {
  value = module.site.github_variables
}
