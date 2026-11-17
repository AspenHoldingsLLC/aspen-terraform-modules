# Staging sign-in (Easy Auth) against Entra. Only users assigned to the enterprise app get through
# (app_role_assignment_required), and the gate covers every revision and label on the staging app.
#
# azurerm has no resource for Container Apps authentication, so the auth config is azapi
# (Microsoft.App/containerApps/authConfigs). There's no client secret: with none set, Easy Auth signs in with the
# OpenID Connect implicit flow and takes only an ID token, which is all a gate needs. Nothing secret enters state.

resource "azuread_application_registration" "staging" {
  display_name                       = local.names.staging_signin
  sign_in_audience                   = "AzureADMyOrg"
  implicit_id_token_issuance_enabled = true
  notes                              = "Easy Auth gate for ${local.names.staging_app}. Managed by Terraform."
}

resource "azuread_application_owner" "staging" {
  for_each = toset(var.operator_object_ids)

  application_id  = azuread_application_registration.staging.id
  owner_object_id = each.value
}

# Terraform sets the staging app's own callback once. The PR workflow (as ghstg) adds one callback per preview label,
# https://<label-host>/.auth/login/aad/callback, and removes it when the PR closes. Terraform ignores later changes to
# the list so the two never fight. Entra allows 256 redirect URIs per app (README, "Preview callbacks").
resource "azuread_application_redirect_uris" "staging" {
  application_id = azuread_application_registration.staging.id
  type           = "Web"
  redirect_uris  = ["https://${azurerm_container_app.staging.ingress[0].fqdn}/.auth/login/aad/callback"]

  lifecycle {
    ignore_changes = [redirect_uris]
  }
}

resource "azuread_service_principal" "staging" {
  client_id                    = azuread_application_registration.staging.client_id
  app_role_assignment_required = true
  owners                       = var.operator_object_ids
}

# The default access role (all zeros) is what "assign users" uses for an app with no roles of its own.
resource "azuread_app_role_assignment" "staging_users" {
  for_each = var.staging_user_object_ids

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.staging.object_id
}

resource "azapi_resource" "staging_auth" {
  type      = "Microsoft.App/containerApps/authConfigs@2025-07-01"
  name      = "current"
  parent_id = azurerm_container_app.staging.id

  body = {
    properties = {
      platform = { enabled = true }
      globalValidation = {
        unauthenticatedClientAction = "RedirectToLoginPage"
        redirectToProvider          = "azureactivedirectory"
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            clientId     = azuread_application_registration.staging.client_id
            openIdIssuer = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
          }
          validation = {
            allowedAudiences = [azuread_application_registration.staging.client_id]
          }
        }
      }
    }
  }
}

# ---- Preview callbacks: ghstg may edit this one app registration and nothing else in Entra ---------------------

# ghstg owns the staging app registration, so Application.ReadWrite.OwnedBy reaches it. ghprod gets nothing in Graph.
resource "azuread_application_owner" "staging_deploy" {
  application_id  = azuread_application_registration.staging.id
  owner_object_id = azurerm_user_assigned_identity.deploy["staging"].principal_id
}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

# Application.ReadWrite.OwnedBy: read and update only the apps the identity owns. Granting it is admin consent to a
# Graph application permission, so the apply needs Privileged Role Administrator or Global Administrator (README).
resource "azuread_app_role_assignment" "deploy_staging_graph" {
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids["Application.ReadWrite.OwnedBy"]
  principal_object_id = azurerm_user_assigned_identity.deploy["staging"].principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
