output "client_id" {
  description = "Application (client) ID. GitHub workflows set it as AZURE_CLIENT_ID or ARM_CLIENT_ID. Not a secret."
  value       = azuread_application_registration.this.client_id
}

output "application_object_id" {
  description = "Object ID of the app registration."
  value       = azuread_application_registration.this.object_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal. Azure role assignments use this as principal_id."
  value       = azuread_service_principal.this.object_id
}

output "graph_app_roles" {
  description = "The Graph application permissions granted."
  value       = sort(tolist(var.graph_app_roles))
}
