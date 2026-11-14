# The tenant's admin group and a check on its emergency access accounts.
#
# The group is a plain security group. It's the principal the landing zone grants Azure roles to once a subscription
# exists, so adding a second admin later is one membership change. It isn't role-assignable: assigning Entra roles to
# a group needs Entra ID P1, and a new tenant is on Free.
#
# Everything here needs only Group.ReadWrite.All and User.Read.All, which an Azure CLI sign-in by an admin has, so a
# landing zone can apply it before it has a deployer service principal.

resource "azuread_group" "admins" {
  display_name            = var.admin_group_name
  description             = "Tenant administrators. Azure roles are granted to this group. Managed by Terraform."
  security_enabled        = true
  mail_enabled            = false
  prevent_duplicate_names = true

  owners  = var.admin_object_ids
  members = var.admin_object_ids
}

# ---- Emergency access accounts ---------------------------------------------------------------------------------

data "azuread_user" "emergency" {
  for_each = var.emergency_access_object_ids

  object_id = each.value

  lifecycle {
    postcondition {
      condition     = self.user_type == "Member" && !self.onpremises_sync_enabled
      error_message = "Emergency access account ${each.value} must be a cloud-only member, not a guest or a synced user."
    }

    postcondition {
      condition     = endswith(lower(self.user_principal_name), ".onmicrosoft.com")
      error_message = "Emergency access account ${each.value} must sign in on the tenant's onmicrosoft.com domain, so it works when a custom domain or federation breaks."
    }
  }
}

check "two_emergency_access_accounts" {
  assert {
    condition     = length(var.emergency_access_object_ids) >= 2
    error_message = "Microsoft recommends two emergency access accounts. This tenant lists ${length(var.emergency_access_object_ids)}."
  }
}
