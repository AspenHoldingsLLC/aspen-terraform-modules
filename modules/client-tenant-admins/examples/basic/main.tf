# Placeholder IDs only. A real landing zone pins exact versions and its own tenant.
terraform {
  required_version = ">= 1.9"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.9, < 4.0"
    }
  }
}

provider "azuread" {
  tenant_id = "00000000-0000-0000-0000-000000000000"
}

module "admins" {
  source = "../.."

  admin_group_name = "grp-example-admins"
  admin_object_ids = ["11111111-1111-1111-1111-111111111111"]

  emergency_access_object_ids = [
    "22222222-2222-2222-2222-222222222222",
    "33333333-3333-3333-3333-333333333333",
  ]
}

output "admin_group_object_id" {
  value = module.admins.admin_group_object_id
}
