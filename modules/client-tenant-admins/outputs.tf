output "admin_group_object_id" {
  description = "Object ID of the admin group. Use it as principal_id for Azure role assignments."
  value       = azuread_group.admins.object_id
}

output "emergency_access_user_principal_names" {
  description = "Sign-in names of the checked emergency access accounts, for exclusion lists such as Conditional Access."
  value       = sort([for u in data.azuread_user.emergency : u.user_principal_name])
}
