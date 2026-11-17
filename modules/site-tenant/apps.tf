# Both apps start on a public placeholder image. Deploys from GitHub replace the image (and on staging, the revisions
# and traffic labels), so Terraform ignores those fields after creation.

resource "azurerm_container_app" "production" {
  name                         = local.names.production_app
  resource_group_name          = azurerm_resource_group.site.name
  container_app_environment_id = local.environment_id
  revision_mode                = "Single"
  workload_profile_name        = local.workload_profile_name
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runtime.id]
  }

  registry {
    server   = local.registry.login_server
    identity = azurerm_user_assigned_identity.runtime.id
  }

  dynamic "secret" {
    for_each = local.portal_secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = azurerm_user_assigned_identity.runtime.id
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.production_min_replicas
    max_replicas = var.production_max_replicas

    container {
      name   = "site"
      image  = var.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.runtime.client_id
      }
      env {
        name  = "BLOB_ENDPOINT"
        value = azurerm_storage_account.site.primary_blob_endpoint
      }
      dynamic "env" {
        for_each = local.portal_env
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = var.portal_sign_in == null ? {} : {
          APP_BASE_URL                 = local.production_base_url
          PORTAL_ACCESS_TABLE_ENDPOINT = azurerm_storage_account.site.primary_table_endpoint
          PORTAL_ACCESS_TABLE          = azurerm_storage_table.portal_access["production"].name
          PORTAL_BUILDS_TABLE          = azurerm_storage_table.portal_builds["production"].name
        }
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = local.portal_secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image, template[0].revision_suffix]
  }

  depends_on = [azurerm_role_assignment.runtime_acr_reader, azurerm_role_assignment.runtime_portal_secrets]
}

# Multiple-revision mode: each PR gets its own revision with a label, and "A label provides a unique URL". The PR
# workflow adds the label, and removes it when the PR closes. Inactive revisions aren't billed.
resource "azurerm_container_app" "staging" {
  name                         = local.names.staging_app
  resource_group_name          = azurerm_resource_group.site.name
  container_app_environment_id = local.environment_id
  revision_mode                = "Multiple"
  workload_profile_name        = local.workload_profile_name
  max_inactive_revisions       = 20
  tags                         = merge(local.tags, { environment = "staging" })

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.staging_runtime.id]
  }

  registry {
    server   = local.registry.login_server
    identity = azurerm_user_assigned_identity.staging_runtime.id
  }

  dynamic "secret" {
    for_each = local.portal_secrets_staging
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = azurerm_user_assigned_identity.staging_runtime.id
    }
  }

  # The AI editor's GitHub token, staging only (var.editor). Production never gets it.
  dynamic "secret" {
    for_each = var.editor == null ? {} : { "editor-github-token" = "${var.editor.key_vault_uri}secrets/${var.editor.token_secret_name}" }
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = azurerm_user_assigned_identity.staging_runtime.id
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "site"
      image  = var.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.staging_runtime.client_id
      }
      env {
        name  = "BLOB_ENDPOINT"
        value = azurerm_storage_account.site.primary_blob_endpoint
      }
      dynamic "env" {
        for_each = local.portal_env
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = var.portal_sign_in == null ? {} : {
          APP_BASE_URL                 = local.staging_base_url
          PORTAL_ACCESS_TABLE_ENDPOINT = azurerm_storage_account.site.primary_table_endpoint
          PORTAL_ACCESS_TABLE          = azurerm_storage_table.portal_access["staging"].name
          PORTAL_BUILDS_TABLE          = azurerm_storage_table.portal_builds["staging"].name
        }
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = local.portal_secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }
      dynamic "env" {
        for_each = var.editor == null ? {} : {
          EDITOR_ENABLED     = "true"
          EDITOR_USERS       = join(",", var.editor.users)
          EDITOR_GITHUB_REPO = var.editor.github_repo
        }
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = var.editor == null ? {} : { EDITOR_GITHUB_TOKEN = "editor-github-token" }
        content {
          name        = env.key
          secret_name = env.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image, template[0].revision_suffix, ingress[0].traffic_weight]
  }

  depends_on = [azurerm_role_assignment.staging_runtime_acr_reader, azurerm_role_assignment.staging_runtime_portal_secrets, azurerm_role_assignment.staging_runtime_editor_token]
}

# ---- Client-portal sign-in (var.portal_sign_in) -------------------------------------------------------------------

locals {
  portal_env = var.portal_sign_in == null ? {} : {
    OIDC_ISSUER    = "https://${var.portal_sign_in.tenant_id}.ciamlogin.com/${var.portal_sign_in.tenant_id}/v2.0"
    OIDC_TENANT_ID = var.portal_sign_in.tenant_id
    OIDC_CLIENT_ID = var.portal_sign_in.client_id
  }
  # Container App secret name => Key Vault secret URL (versionless, so a rotated value is picked up on restart).
  portal_secrets = var.portal_sign_in == null ? {} : {
    "oidc-client-secret" = "${var.portal_sign_in.key_vault_uri}secrets/${var.portal_sign_in.client_secret_name}"
    "session-secret"     = "${var.portal_sign_in.key_vault_uri}secrets/${var.portal_sign_in.session_secret_name}"
  }
  # Staging seals its cookies with its own key: a PR preview can read every secret it's given, and with production's
  # key it could forge a production session carrying the owner role. The OIDC client secret is shared, because both
  # apps use the one portal app registration; on its own it grants no access to anything.
  portal_secrets_staging = var.portal_sign_in == null ? {} : {
    "oidc-client-secret" = "${var.portal_sign_in.key_vault_uri}secrets/${var.portal_sign_in.client_secret_name}"
    "session-secret"     = "${var.portal_sign_in.key_vault_uri}secrets/${var.portal_sign_in.staging_session_secret_name}"
  }
  # The portal access list, one table per app. Staging and PR previews share the staging one.
  portal_access_tables = var.portal_sign_in == null ? {} : {
    production = "portalaccess"
    staging    = "portalaccessstaging"
  }
  # The build tracker, same split.
  portal_builds_tables = var.portal_sign_in == null ? {} : {
    production = "portalbuilds"
    staging    = "portalbuildsstaging"
  }
  portal_secret_env = var.portal_sign_in == null ? {} : {
    OIDC_CLIENT_SECRET = "oidc-client-secret"
    SESSION_SECRET     = "session-secret"
  }
}

resource "azurerm_role_assignment" "runtime_portal_secrets" {
  for_each = var.portal_sign_in == null ? toset([]) : toset([var.portal_sign_in.client_secret_name, var.portal_sign_in.session_secret_name])

  scope                = "${var.portal_sign_in.key_vault_id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "staging_runtime_portal_secrets" {
  for_each = var.portal_sign_in == null ? toset([]) : toset([var.portal_sign_in.client_secret_name, var.portal_sign_in.staging_session_secret_name])

  scope                = "${var.portal_sign_in.key_vault_id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.staging_runtime.principal_id
  principal_type       = "ServicePrincipal"
}

# ---- AI editor (var.editor), staging only ------------------------------------------------------------------------

# Only the staging identity can read the editor's GitHub token. Production's identity has no route to it.
resource "azurerm_role_assignment" "staging_runtime_editor_token" {
  for_each = var.editor == null ? toset([]) : toset([var.editor.token_secret_name])

  scope                = "${var.editor.key_vault_id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.staging_runtime.principal_id
  principal_type       = "ServicePrincipal"
  description          = "The AI editor's GitHub token, read by the staging app only"
}
