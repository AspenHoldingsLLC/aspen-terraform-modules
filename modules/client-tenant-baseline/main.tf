# Tenant-wide settings a new Entra tenant gets wrong for a small business: who may invite guests, register apps,
# create tenants and groups, and join by email. Plus inbound MFA trust for the operator's home tenant.
#
# The hashicorp/azuread provider has no resource for either object, so this uses Microsoft's msgraph provider.
#
# Permissions. An Azure CLI sign-in can't write these: its Graph token carries no Policy.* scopes. Apply this module
# as a service principal with the Graph application permissions Policy.Read.All, Policy.ReadWrite.Authorization and,
# when home_tenant_id is set, Policy.ReadWrite.CrossTenantAccess (the github-oidc-deployer module can grant them). A
# CLI sign-in can still plan it, since reading both objects needs no Policy scope.

# The authorization policy is a singleton that every tenant already has. msgraph_update_resource PATCHes the listed
# properties and leaves the rest alone. There's nothing to import, and removing this from Terraform changes nothing in
# the tenant. Values set by hand before the first apply are simply asserted again.
resource "msgraph_update_resource" "authorization_policy" {
  url = "policies/authorizationPolicy"

  body = {
    allowInvitesFrom                          = var.guest_invite_policy
    allowedToSignUpEmailBasedSubscriptions    = var.email_self_service_signup
    allowEmailVerifiedUsersToJoinOrganization = var.email_self_service_signup
    defaultUserRolePermissions = {
      allowedToCreateApps                      = var.users_can_create_apps
      allowedToCreateTenants                   = var.users_can_create_tenants
      allowedToCreateSecurityGroups            = var.users_can_create_security_groups
      allowedToReadOtherUsers                  = var.users_can_read_other_users
      allowedToReadBitlockerKeysForOwnedDevice = var.users_can_read_own_bitlocker_keys
    }
  }

  response_export_values = {
    allow_invites_from = "allowInvitesFrom"
  }
}

# A partner configuration for the home tenant, trusting its MFA claims. Device claims aren't trusted: the operator's
# devices aren't managed by this tenant. If the configuration was created by hand first, import it with the ID
# "policies/crossTenantAccessPolicy/partners/<home tenant ID>" (README, "Settings made by hand").
resource "msgraph_resource" "home_tenant_partner" {
  count = var.home_tenant_id == null ? 0 : 1

  url = "policies/crossTenantAccessPolicy/partners"

  body = {
    tenantId = var.home_tenant_id
    inboundTrust = {
      isMfaAccepted                       = true
      isCompliantDeviceAccepted           = false
      isHybridAzureADJoinedDeviceAccepted = false
    }
  }
}
