# client-tenant-admins

The tenant's admin security group, and a check on its emergency access accounts.

## What it creates

- A security group (`admin_group_name`) whose members and owners are `admin_object_ids`. The landing zone grants Azure
  roles to this group, so adding a second admin is one membership change.

## What it checks

- Each ID in `emergency_access_object_ids` exists, is a cloud-only member, and signs in on the
  tenant's `onmicrosoft.com` domain. A failed check fails the plan.
- There are at least two. Fewer gives a warning, not an error, so the module can run before the accounts exist.

The emergency access accounts themselves are created by hand. Their passkeys are registered in person, and a password
set through Terraform would sit in state. Microsoft's guidance is
[Manage emergency access accounts](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access).

## Why the group isn't role-assignable

Assigning an Entra role to a group needs Entra ID P1. A new tenant is on Free. Entra roles stay assigned to people
directly, and the group carries Azure roles only.

## Who can apply it

An Azure CLI sign-in by an admin. It needs `Group.ReadWrite.All` and `User.Read.All`, which the CLI's Graph token
has. So a landing zone can apply it before it has a deployer service principal.

## Usage

```hcl
module "admins" {
  source = "git::https://github.com/AspenHoldingsLLC/aspen-terraform-modules.git//modules/client-tenant-admins?ref=v0.1.0"

  admin_group_name            = "grp-<client>-admins"
  admin_object_ids            = [local.operator_object_id]
  emergency_access_object_ids = local.emergency_access_object_ids
}
```

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `admin_group_name` | string | | Required |
| `admin_object_ids` | set(string) | | Required, at least one |
| `emergency_access_object_ids` | set(string) | `[]` | Two, once they exist |

## Outputs

- `admin_group_object_id`: use it as the principal for Azure role assignments.
- `emergency_access_user_principal_names`: for exclusion lists such as Conditional Access, once the tenant has P1.
