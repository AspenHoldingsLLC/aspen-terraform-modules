output "guest_invite_policy" {
  description = "allowInvitesFrom as Graph returns it after the apply."
  value       = msgraph_update_resource.authorization_policy.output.allow_invites_from
}

output "home_tenant_trusted" {
  description = "Whether a partner configuration trusting the home tenant's MFA is managed here."
  value       = var.home_tenant_id != null
}
