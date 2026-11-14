variable "resource_group_name" {
  description = "Resource group for the state account."
  type        = string
}

variable "create_resource_group" {
  description = "Create the resource group. False uses an existing one with this name."
  type        = bool
  default     = true
}

variable "location" {
  description = "Azure region, for example eastus2."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique, 3-24 lower-case letters and digits."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name is 3-24 lower-case letters and digits."
  }
}

variable "container_name" {
  description = "Blob container that holds the state files. Each layer uses its own key in it."
  type        = string
  default     = "tfstate"
}

variable "data_contributor_principal_ids" {
  description = <<-EOT
    Principals that read and write state, by a short name: the deployer service principal and the admin group, for
    example. Each gets Storage Blob Data Contributor on the account. Owner on the subscription doesn't include it.
  EOT
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "Days a deleted or overwritten state blob, or a deleted container, can be recovered."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 365
    error_message = "retention_days is 7-365."
  }
}

variable "tags" {
  description = "Tags for the resource group and the account."
  type        = map(string)
  default     = {}
}
