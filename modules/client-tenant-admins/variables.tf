variable "admin_group_name" {
  description = "Display name of the admin security group, for example grp-<client>-admins."
  type        = string

  validation {
    condition     = length(trimspace(var.admin_group_name)) > 0
    error_message = "admin_group_name can't be empty."
  }
}

variable "admin_object_ids" {
  description = "Object IDs of the people who run the tenant day to day. They become the group's members and owners."
  type        = set(string)

  validation {
    condition     = length(var.admin_object_ids) > 0
    error_message = "Give at least one admin."
  }
}

variable "emergency_access_object_ids" {
  description = <<-EOT
    Object IDs of the tenant's emergency access (break-glass) accounts. They're created by hand, because their
    passkeys are registered in person and a password set here would sit in state. The module checks each one is a
    cloud-only member on the tenant's onmicrosoft.com domain. Empty until the accounts exist.
  EOT
  type        = set(string)
  default     = []
}
