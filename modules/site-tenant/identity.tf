# Four identities per customer, so no single credential can do everything:
#   runtime          - what production runs as: pull the customer's images, read and write the customer's blobs and
#                      the production portal tables
#   staging runtime  - what staging and every PR preview run as: pull images, the staging portal tables, and photo
#                      uploads under portfolio/uploads/. Nothing of production's.
#   ghprod           - GitHub deploys to production (environment "production" only)
#   ghstg            - GitHub deploys to staging and PR previews (environment "staging" and pull_request)
# A pull request can't deploy production, because no PR token matches the ghprod subject. It can't borrow
# production's identity either: ghstg may assign only the staging runtime identity to an app.

resource "azurerm_user_assigned_identity" "runtime" {
  name                = local.names.runtime_identity
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  tags                = local.tags
}

# PR previews run branch code nobody has reviewed yet, so the identity they run as gets only staging's data.
resource "azurerm_user_assigned_identity" "staging_runtime" {
  name                = local.names.staging_runtime_identity
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  tags                = merge(local.tags, { environment = "staging" })
}

resource "azurerm_user_assigned_identity" "deploy" {
  for_each = local.deploy

  name                = each.value.name
  resource_group_name = azurerm_resource_group.site.name
  location            = var.location
  tags                = local.tags
}

locals {
  deploy = {
    prod = {
      name     = local.names.deploy_prod
      subjects = { production = "environment:production" }
    }
    staging = {
      name = local.names.deploy_staging
      subjects = {
        staging      = "environment:staging"
        pull-request = "pull_request"
      }
    }
  }

  deploy_subjects = merge([
    for id, d in local.deploy : {
      for k, s in d.subjects : "${id}-${k}" => { identity = id, name = k, subject = s }
    }
  ]...)

  deploy_app_ids = {
    prod    = azurerm_container_app.production.id
    staging = azurerm_container_app.staging.id
  }

  # The identity each app runs as, by deploy key and by portal table key.
  app_runtime = {
    prod    = azurerm_user_assigned_identity.runtime
    staging = azurerm_user_assigned_identity.staging_runtime
  }
  table_runtime = {
    production = azurerm_user_assigned_identity.runtime
    staging    = azurerm_user_assigned_identity.staging_runtime
  }

  # The ABAC condition that limits a registry role to the customer's repositories. Actions the condition doesn't
  # name pass through untouched, so every data action the role grants is listed.
  acr_actions = {
    reader = [
      "Microsoft.ContainerRegistry/registries/repositories/content/read",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
    ]
    writer = [
      "Microsoft.ContainerRegistry/registries/repositories/content/read",
      "Microsoft.ContainerRegistry/registries/repositories/content/write",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/write",
    ]
  }

  acr_condition = {
    for role, actions in local.acr_actions : role => format(
      "((%s) OR (@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '%s'))",
      join(" AND ", [for a in actions : "!(ActionMatches{'${a}'})"]),
      local.acr_repository_prefix,
    )
  }
}

# The subject pins the org and repo by immutable ID, plus the environment or event.
resource "azurerm_federated_identity_credential" "github" {
  for_each = local.deploy_subjects

  name                      = "gh-${var.key}-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy[each.value.identity].id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "${var.github_subject_prefix}:${each.value.subject}"
}

# ---- Registry: repository-scoped (the registry runs in ABAC mode, where AcrPull and AcrPush aren't honored) ------

resource "azurerm_role_assignment" "runtime_acr_reader" {
  scope                = local.registry.id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.acr_condition.reader
  description          = "Pull ${local.acr_repository_prefix}* only"
}

resource "azurerm_role_assignment" "staging_runtime_acr_reader" {
  scope                = local.registry.id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = azurerm_user_assigned_identity.staging_runtime.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.acr_condition.reader
  description          = "Pull ${local.acr_repository_prefix}* only"
}

resource "azurerm_role_assignment" "deploy_acr_writer" {
  for_each = azurerm_user_assigned_identity.deploy

  scope                = local.registry.id
  role_definition_name = "Container Registry Repository Writer"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.acr_condition.writer
  description          = "Push and pull ${local.acr_repository_prefix}* only"
}

# ---- Deploy rights: each deploy identity on its own app only ---------------------------------------------------

resource "azurerm_role_assignment" "deploy_app" {
  for_each = azurerm_user_assigned_identity.deploy

  scope                = local.deploy_app_ids[each.key]
  role_definition_name = "Container Apps Contributor"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}

# An app update sends the app's identity block back to ARM, which checks assign rights on that identity. Each deploy
# identity may assign only its own app's runtime identity, so a PR workflow can't put production's on staging.
resource "azurerm_role_assignment" "deploy_runtime_identity" {
  for_each = azurerm_user_assigned_identity.deploy

  scope                = local.app_runtime[each.key].id
  role_definition_name = "Managed Identity Operator"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}

# az containerapp update reads the environment. Reader on it shows its settings and nothing else.
resource "azurerm_role_assignment" "deploy_environment_reader" {
  for_each = azurerm_user_assigned_identity.deploy

  scope                = local.environment_id
  role_definition_name = "Reader"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}

# ---- Blob data -------------------------------------------------------------------------------------------------

# Production reads and writes its own blobs and signs short-lived links for portal photos (user delegation SAS).
resource "azurerm_role_assignment" "runtime_blob" {
  scope                = azurerm_storage_account.site.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
  principal_type       = "ServicePrincipal"
}

# The AI editor runs on staging and uploads photos to portfolio/uploads/, which the public site then links to. Staging may read the portfolio container, but it may write and delete under uploads/
# only, so a PR preview can't replace or remove a published site image. It gets nothing on the private portal
# container. (Versioning and permanent delete are off on the account, so write, add and delete are every change.)
locals {
  staging_upload_actions = [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
  ]
  staging_upload_condition = format(
    "((%s) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers/blobs:path] StringStartsWith 'uploads/'))",
    join(" AND ", [for a in local.staging_upload_actions : "!(ActionMatches{'${a}'})"]),
  )
}

resource "azurerm_role_assignment" "staging_runtime_uploads" {
  scope                = azurerm_storage_container.portfolio.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.staging_runtime.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.staging_upload_condition
  description          = "Change portfolio/uploads/* only"
}

# Production deploys can publish portfolio images; nothing in GitHub touches the private portal container.
resource "azurerm_role_assignment" "deploy_prod_portfolio" {
  scope                = azurerm_storage_container.portfolio.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy["prod"].principal_id
  principal_type       = "ServicePrincipal"
}

# ---- Table data: the portal access list ------------------------------------------------------------------------

# The app reads each person's entry on every portal request and writes the binding on first sign-in and the owners'
# changes from /portal/admin. Each app's runtime identity gets its own table only: production can't touch staging's
# list, and staging and PR previews can't touch production's, where an entry can grant owner.
resource "azurerm_role_assignment" "runtime_portal_access" {
  for_each = azurerm_storage_table.portal_access

  scope                = each.value.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = local.table_runtime[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# Operators seed and repair the list from the command line.
resource "azurerm_role_assignment" "operator_portal_access" {
  for_each = {
    for pair in setproduct(keys(azurerm_storage_table.portal_access), var.operator_object_ids) :
    "${pair[0]}-${pair[1]}" => { table = pair[0], principal = pair[1] }
  }

  scope                = azurerm_storage_table.portal_access[each.value.table].id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = each.value.principal
  principal_type       = "User"
}

resource "azurerm_role_assignment" "runtime_portal_builds" {
  for_each = azurerm_storage_table.portal_builds

  scope                = each.value.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = local.table_runtime[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# Operators back up and bulk-load the tracker from the command line.
resource "azurerm_role_assignment" "operator_portal_builds" {
  for_each = {
    for pair in setproduct(keys(azurerm_storage_table.portal_builds), var.operator_object_ids) :
    "${pair[0]}-${pair[1]}" => { table = pair[0], principal = pair[1] }
  }

  scope                = azurerm_storage_table.portal_builds[each.value.table].id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = each.value.principal
  principal_type       = "User"
}
