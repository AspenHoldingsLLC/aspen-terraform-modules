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

module "deployer" {
  source = "../.."

  display_name = "app-example-terraform"
  notes        = "Terraform deployer for example-org/example-landing-zone."

  github_subjects = {
    production = "repo:example-org/example-landing-zone:environment:production"
  }

  graph_app_roles = [
    "Policy.Read.All",
    "Policy.ReadWrite.Authorization",
  ]

  owner_object_ids = ["11111111-1111-1111-1111-111111111111"]
}

output "client_id" {
  value = module.deployer.client_id
}
