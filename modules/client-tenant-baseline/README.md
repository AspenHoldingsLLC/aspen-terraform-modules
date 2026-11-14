# client-tenant-baseline

Tenant-wide settings a new Entra tenant gets wrong for a small business, plus MFA trust for the operator's home
tenant.

## What it sets

| Setting | A new tenant | This module's default | Variable |
|---|---|---|---|
| Who may invite guests | everyone | admins and the Guest Inviter role | `guest_invite_policy` |
| Users may register apps | yes | no | `users_can_create_apps` |
| Users may create tenants | yes | no | `users_can_create_tenants` |
| Users may create security groups | yes | no | `users_can_create_security_groups` |
| Email sign-up and join by verified email | yes | no | `email_self_service_signup` |
| Users may read other users | yes | yes | `users_can_read_other_users` |
| Users may read their own devices' BitLocker keys | yes | yes | `users_can_read_own_bitlocker_keys` |
| Inbound MFA trust for one partner tenant | none | set when `home_tenant_id` is given | `home_tenant_id` |

The first seven live in the tenant's authorization policy. The last is a partner entry in its cross-tenant access
settings. Device claims from the home tenant aren't trusted, since this tenant doesn't manage those devices.

User consent to apps is left at Microsoft's default. Change it in the Entra admin center if a client needs it tighter.

## How it applies

The `hashicorp/azuread` provider has no resource for either object, so this uses Microsoft's `msgraph` provider.

- **Authorization policy.** Every tenant has exactly one. `msgraph_update_resource` sends a PATCH with the listed
  properties and leaves the rest alone. There's nothing to import, and removing the module changes nothing in the
  tenant. If the values were set by hand first, the first apply sets them again.
- **Partner entry.** `msgraph_resource` creates it. If it was created by hand first, import it:

  ```hcl
  import {
    to = module.baseline.msgraph_resource.home_tenant_partner[0]
    id = "policies/crossTenantAccessPolicy/partners/<home tenant ID>"
  }
  ```

## Who can apply it

**Not an Azure CLI sign-in.** The CLI's Graph token has no `Policy.*` scopes, so a PATCH fails with "required scopes
are missing". Apply it as a service principal with these Graph application permissions:

- `Policy.Read.All`
- `Policy.ReadWrite.Authorization`
- `Policy.ReadWrite.CrossTenantAccess`, when `home_tenant_id` is set

The [`github-oidc-deployer`](../github-oidc-deployer/README.md) module grants them. A CLI sign-in can still run
`terraform plan`, since reading both objects needs no `Policy.*` scope.

## Usage

```hcl
module "baseline" {
  source = "git::https://github.com/AspenHoldingsLLC/aspen-terraform-modules.git//modules/client-tenant-baseline?ref=v0.1.0"

  home_tenant_id = local.operator_home_tenant_id
}
```

## Outputs

`guest_invite_policy`, as Graph returns it after the apply, and `home_tenant_trusted`.

## Not yet verified

The partner entry's create call returns no top-level `id`. The provider then takes the ID from the response's
`Location` header. We haven't run that against a tenant yet. The first apply is the test: if it fails, create the
entry by hand and import it as above.
