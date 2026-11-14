# An app registration and service principal that GitHub Actions signs in as through OIDC. It has no secret and no
# certificate: the only way in is a token from the issuer with one of the configured subjects.
#
# Azure roles aren't granted here. The landing zone assigns them once a subscription exists, scoped as narrowly as it
# can.

resource "azuread_application_registration" "this" {
  display_name     = var.display_name
  sign_in_audience = "AzureADMyOrg"
  notes            = var.notes
}

resource "azuread_application_owner" "this" {
  for_each = var.owner_object_ids

  application_id  = azuread_application_registration.this.id
  owner_object_id = each.value
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application_registration.this.client_id
  owners    = var.owner_object_ids
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each = var.github_subjects

  application_id = azuread_application_registration.this.id
  display_name   = each.key
  description    = "GitHub Actions, ${each.value}"
  audiences      = [var.audience]
  issuer         = var.issuer
  subject        = each.value
}

# ---- Microsoft Graph application permissions -------------------------------------------------------------------

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

resource "azuread_app_role_assignment" "graph" {
  for_each = var.graph_app_roles

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.this.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
