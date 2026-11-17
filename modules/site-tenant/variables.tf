variable "key" {
  description = "Short customer key used in every name: lowercase letters and digits, 2-15 characters (cap-<key>-staging-<region> must fit Container Apps' 32-character limit)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,14}$", var.key))
    error_message = "Use 2-15 lowercase letters and digits, starting with a letter."
  }
}

variable "location" {
  description = "Region for the customer's resources. Must match the environment's, if a shared one is passed."
  type        = string
}

variable "region_code" {
  description = "Short region code for names, e.g. eus2."
  type        = string
}

variable "owner" {
  description = "Value of the owner tag."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant for the staging sign-in."
  type        = string
}

variable "container_app_environment_id" {
  description = "A shared Consumption environment. Null creates cae-<key>-<region> for this customer alone."
  type        = string
  default     = null
}

variable "container_app_environment_name" {
  description = "Name of the shared environment. Needed only with container_app_environment_id."
  type        = string
  default     = null

  validation {
    condition     = (var.container_app_environment_name == null) == (var.container_app_environment_id == null)
    error_message = "Pass container_app_environment_name and container_app_environment_id together, or neither."
  }
}

variable "workload_profile_name" {
  description = "With a shared environment: the workload profile the apps run on. Null for a Consumption-only environment (one created before workload profiles were the default). Ignored when the module creates the environment, which uses its built-in Consumption profile."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Where the customer's own environment sends its logs. Ignored when a shared environment is passed. Null sends them nowhere."
  type        = string
  default     = null
}

variable "container_registry" {
  description = "A shared registry, in ABAC mode. The customer's images live under <key>/ in it. Null creates acr<key><region> (Basic, ABAC mode) for this customer alone."
  type = object({
    id           = string
    login_server = string
  })
  default = null
}

variable "storage_account_name" {
  description = "Overrides the storage account name, sta<key><region>. Storage names are global, so a rebuild next to an old account needs a new one."
  type        = string
  default     = null
}

variable "github_subject_prefix" {
  description = "The repo's OIDC subject prefix as GitHub reports it (GET /repos/<owner>/<repo>/actions/oidc/customization/sub), e.g. repo:Org@123/repo@456."
  type        = string
}

variable "operator_object_ids" {
  description = "Owners of the staging app registration (object IDs)."
  type        = list(string)
}

variable "staging_user_object_ids" {
  description = "Users allowed through the staging sign-in, by name => object ID. Nobody else gets in (assignment required)."
  type        = map(string)
}

variable "placeholder_image" {
  description = "Public image the apps start with, so they exist before the site is built. Deploys replace it and Terraform ignores the change."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "target_port" {
  description = "Port the container listens on. The placeholder uses 80; a Next.js standalone server uses 3000."
  type        = number
  default     = 80
}

variable "production_min_replicas" {
  description = "0 scales production to zero (cold start after 5 idle minutes). 1 keeps it warm for about $6/month."
  type        = number
  default     = 0

  validation {
    condition     = var.production_min_replicas >= 0 && var.production_min_replicas <= 2
    error_message = "Use 0, 1 or 2."
  }
}

variable "production_max_replicas" {
  description = "Upper bound on production replicas."
  type        = number
  default     = 2
}

variable "custom_domains" {
  description = "Hostnames to bind to production later. Not bound yet: listed here so the plan for them is in code."
  type        = list(string)
  default     = []
}

variable "portal_sign_in" {
  description = <<-EOT
    Client-portal sign-in through a Microsoft Entra External ID tenant. Null leaves it off. Each app's runtime identity reads the client secret and that app's own session key from Key
    Vault, with Key Vault Secrets User on those two secrets only, so no value is ever in Terraform state.
  EOT
  type = object({
    tenant_id           = string
    client_id           = string
    key_vault_id        = string
    key_vault_uri       = string
    client_secret_name  = string
    session_secret_name = string
    # Staging's own cookie key, so a staging or PR-preview session can never be replayed against production.
    staging_session_secret_name = string
    # Each app's public address, for the sign-in callback. Null uses the app's generated hostname.
    production_base_url = optional(string)
    staging_base_url    = optional(string)
  })
  default = null
}

variable "editor" {
  description = <<-EOT
    The AI editor on the staging app only. Null turns it off. The GitHub token is read from Key Vault by the staging
    runtime identity, the only identity that can read that one secret. users are Easy Auth sign-in names
    (x-ms-client-principal-name), which for Entra is the user principal name.
  EOT
  type = object({
    github_repo       = string       # owner/name
    users             = list(string) # sign-in names allowed to use the editor
    key_vault_id      = string
    key_vault_uri     = string
    token_secret_name = string
  })
  default = null

  validation {
    condition     = var.editor == null || (can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.editor.github_repo)) && length(var.editor.users) > 0)
    error_message = "editor.github_repo is owner/name, and editor.users names at least one person."
  }
}
