# Placeholder IDs only. A real landing zone pins exact versions and its own tenant.
terraform {
  required_version = ">= 1.9"

  required_providers {
    msgraph = {
      source  = "Microsoft/msgraph"
      version = ">= 0.6.0, < 1.0.0"
    }
  }
}

provider "msgraph" {
  tenant_id = "00000000-0000-0000-0000-000000000000"
}

module "baseline" {
  source = "../.."

  # The secure defaults, spelled out.
  guest_invite_policy       = "adminsAndGuestInviters"
  users_can_create_apps     = false
  users_can_create_tenants  = false
  email_self_service_signup = false

  home_tenant_id = "44444444-4444-4444-4444-444444444444"
}

output "guest_invite_policy" {
  value = module.baseline.guest_invite_policy
}
