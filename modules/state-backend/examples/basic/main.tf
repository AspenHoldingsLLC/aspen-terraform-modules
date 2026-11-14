# Placeholder IDs only. A real landing zone pins exact versions and its own tenant and subscription.
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.10, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}

  tenant_id           = "00000000-0000-0000-0000-000000000000"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  storage_use_azuread = true

  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Storage"]
}

module "state" {
  source = "../.."

  resource_group_name  = "rgp-terraform-eus2"
  location             = "eastus2"
  storage_account_name = "staexampletfstateeus2"

  data_contributor_principal_ids = {
    deployer = "55555555-5555-5555-5555-555555555555"
    admins   = "66666666-6666-6666-6666-666666666666"
  }

  tags = {
    environment = "platform"
    workload    = "terraform"
    managed-by  = "terraform"
  }
}

output "backend" {
  value = module.state.backend
}
