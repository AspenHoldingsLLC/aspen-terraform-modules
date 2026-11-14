variable "guest_invite_policy" {
  description = <<-EOT
    Who may invite guests: none, adminsAndGuestInviters, adminsGuestInvitersAndAllMembers or everyone. A new tenant
    starts at everyone.
  EOT
  type        = string
  default     = "adminsAndGuestInviters"

  validation {
    condition     = contains(["none", "adminsAndGuestInviters", "adminsGuestInvitersAndAllMembers", "everyone"], var.guest_invite_policy)
    error_message = "guest_invite_policy is one of none, adminsAndGuestInviters, adminsGuestInvitersAndAllMembers or everyone."
  }
}

variable "users_can_create_apps" {
  description = "Whether ordinary users may register applications. A new tenant starts at true."
  type        = bool
  default     = false
}

variable "users_can_create_tenants" {
  description = "Whether ordinary users may create tenants. A new tenant starts at true."
  type        = bool
  default     = false
}

variable "users_can_create_security_groups" {
  description = "Whether ordinary users may create security groups. A new tenant starts at true."
  type        = bool
  default     = false
}

variable "users_can_read_other_users" {
  description = "Whether ordinary users may read other users' profiles. Leave true: Teams and Outlook need it."
  type        = bool
  default     = true
}

variable "users_can_read_own_bitlocker_keys" {
  description = "Whether users may read the BitLocker keys of devices they own. A new tenant starts at true."
  type        = bool
  default     = true
}

variable "email_self_service_signup" {
  description = <<-EOT
    Whether people with an email address on a verified domain may sign up for Microsoft services and join the tenant
    on their own. A new tenant starts at true.
  EOT
  type        = bool
  default     = false
}

variable "home_tenant_id" {
  description = <<-EOT
    Tenant ID of the operator's home tenant. When set, this tenant trusts MFA done there, so an operator signed in at
    home isn't asked again here. Null leaves cross-tenant access settings alone.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.home_tenant_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.home_tenant_id))
    error_message = "home_tenant_id is a tenant GUID in lower case, or null."
  }
}
