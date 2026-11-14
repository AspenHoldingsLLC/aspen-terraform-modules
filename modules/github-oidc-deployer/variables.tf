variable "display_name" {
  description = "Display name of the app registration, for example app-<client>-terraform."
  type        = string

  validation {
    condition     = length(trimspace(var.display_name)) > 0
    error_message = "display_name can't be empty."
  }
}

variable "notes" {
  description = "Free text stored on the app registration. Say which repo manages it."
  type        = string
  default     = null
}

variable "github_subjects" {
  description = <<-EOT
    One federated credential per entry: a short name and the GitHub OIDC subject it trusts. Read the repo's subject
    prefix with `gh api repos/<org>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix`, then add the
    context, for example `<prefix>:environment:production`.
  EOT
  type        = map(string)

  validation {
    condition     = length(var.github_subjects) > 0 && alltrue([for s in values(var.github_subjects) : startswith(s, "repo:")])
    error_message = "Give at least one subject, and every subject starts with \"repo:\"."
  }

  validation {
    condition     = alltrue([for k in keys(var.github_subjects) : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,99}$", k))])
    error_message = "Credential names are letters, digits and hyphens, up to 100 characters."
  }
}

variable "graph_app_roles" {
  description = <<-EOT
    Microsoft Graph application permissions to grant, by value, for example ["Policy.ReadWrite.Authorization"].
    Granting one is admin consent, so the apply needs Privileged Role Administrator or Global Administrator.
  EOT
  type        = set(string)
  default     = []
}

variable "owner_object_ids" {
  description = "Object IDs of users who own the app registration and service principal."
  type        = set(string)
  default     = []
}

variable "issuer" {
  description = "Token issuer. The default is GitHub.com's Actions issuer."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "audience" {
  description = "Token audience Entra expects for workload identity federation."
  type        = string
  default     = "api://AzureADTokenExchange"
}
