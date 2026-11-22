# site-tenant

One customer's website on Azure Container Apps: a public production app, a staging app behind Entra sign-in where PR
previews run as labeled revisions, blob storage, an optional client portal and AI editor, and the GitHub OIDC trust
for the customer's site repo. Each identity reaches only what its job needs.

The Container Apps environment and the registry can be shared by several customers (pass their IDs) or created for
this customer alone (leave `container_app_environment_id` and `container_registry` null).

Names below use the key `abc` in region `eus2`.

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rgp-abc-eus2` | everything below |
| Container Apps environment | `cae-abc-eus2`, only when none is passed | Consumption. Logs to `log_analytics_workspace_id` through a diagnostic setting |
| Registry | `acrabceus2`, only when none is passed | Basic, ABAC mode, no admin user, no anonymous pull |
| Runtime identity | `uai-abc-eus2` | production runs as it. It pulls `abc/*` images only, has Blob Data Contributor on the customer's storage and reaches the production portal tables |
| Staging runtime identity | `uai-abc-staging-eus2` | staging and every PR preview run as it. It pulls `abc/*` images, reaches the staging portal tables only, may change blobs under `portfolio/uploads/` only (the AI editor's photos), and seals cookies with its own session key. It gets nothing of production's |
| Production app | `cap-abc-eus2` | public ingress, single revision, `production_min_replicas` (default 0) |
| Staging app | `cap-abc-staging-eus2` | min 0, max 1, **multiple-revision mode** for per-PR labels, Easy Auth gate |
| Staging sign-in | Entra app `app-abc-staging` | assignment required; only users given its default access role get in |
| Storage | `staabceus2`, or `storage_account_name` | Entra only. `portfolio` is public read; `portal` is private |
| Portal access list | tables `portalaccess`, `portalaccessstaging` | email => roles for the client portal. Created only when `portal_sign_in` is set |
| Build tracker | tables `portalbuilds`, `portalbuildsstaging` | the portal's project data. Same roles and scoping as the access list |
| Sign-up gate | `func-abc-gate-eus2` (Flex Consumption), `uai-abc-gate-eus2`, `stgateabceus2`, `appi-abc-gate-eus2` | External ID calls it before the sign-up form; it refuses emails on neither access list. Its identity reads the two access tables only. Created only when `portal_signup_gate` is set (and `portal_sign_in`) |
| Deploy identities | `uai-abc-ghprod-eus2`, `uai-abc-ghstg-eus2` | GitHub OIDC, no secrets. Push `abc/*` only, deploy their own app only |

## Calling it

```hcl
module "site" {
  source = "git::https://github.com/AspenHoldingsLLC/aspen-terraform-modules.git//modules/site-tenant?ref=v0.2.0"

  key         = "abc"
  location    = "eastus2"
  region_code = "eus2"
  owner       = "Example Ltd"
  tenant_id   = "<the customer's tenant ID>"

  # Own environment and registry: leave container_app_environment_id and container_registry out.
  log_analytics_workspace_id = "<workspace resource ID>"

  github_subject_prefix = "repo:<org>@<org id>/<repo>@<repo id>"
  operator_object_ids   = ["<operator object ID>"]

  # Empty: people are given the staging app's default access role outside Terraform.
  staging_user_object_ids = {}
}
```

`examples/basic` is a complete call with placeholder IDs.

**Who applies it:** an operator with Owner on the subscription and Global Administrator or Privileged Role
Administrator in the tenant, because it grants a Microsoft Graph application permission (below). The Key Vault secrets
named in `portal_sign_in` and `editor` must exist before the apply: the apps reference them.

## GitHub OIDC

Two deploy identities, so a pull request can never deploy production:

| Identity | Trusted subject | Can |
|---|---|---|
| `ghprod` | `<prefix>:environment:production` | push `<key>/*`, update the production app, write the `portfolio` container |
| `ghstg` | `<prefix>:environment:staging`, `<prefix>:pull_request` | push `<key>/*`, update the staging app (revisions and labels), assign the staging runtime identity only, edit the redirect URIs of `app-<key>-staging` (below) |

**Why staging has its own runtime identity:** a PR preview runs branch code that nobody has reviewed yet. When staging
ran as production's identity, that code could write the production access list, where an entry can grant `owner`, and
read production's cookie key, which would let it forge a production session. Now `ghstg` can't even attach
production's identity to the staging app, because its Managed Identity Operator role covers the staging identity only.

The prefix pins the org and repo by immutable ID. The site repo needs GitHub environments named `production` and
`staging`, and `production` is where to add required reviewers.

**Deploy by digest, not tag.** Scale-to-zero replicas pull the image again on every cold start, so a moved tag would
change what's running without a deploy.

## Easy Auth on staging: azapi, no secret

azurerm has no resource for Container Apps authentication, so the auth config is
`azapi_resource` `Microsoft.App/containerApps/authConfigs@2025-07-01`. It has no client secret: Easy Auth then uses
the OpenID Connect implicit flow and takes an ID token only, which is enough for a gate, and nothing secret enters
state.

## Preview callbacks

Each labeled staging revision has its own hostname, and Easy Auth only completes a sign-in if that hostname's callback
is on the staging app registration. The PR workflow manages them, signed in as `ghstg`:

- **On open or update:** add `https://<label-host>/.auth/login/aad/callback`, where `<label-host>` is
  `<staging app>---<label>.<environment default domain>`, for example
  `cap-abc-staging-eus2---pr-12.<default domain>`. The workflow reads the current list, appends, and writes it
  back through Graph (`PATCH /applications(appId='<STAGING_SIGNIN_APP_CLIENT_ID>')`, `web.redirectUris`).
- **On close or merge:** remove that URI in the same way, along with the revision label.
- **Limits:** Entra allows **256 redirect URIs** per app that signs in only this tenant's accounts, at most 256
  characters each. Wildcards are discouraged. The workflow must clean up on close, or open PRs plus leftovers will
  eventually hit the cap.
- **Terraform doesn't fight it.** It sets the staging app's own callback once and ignores later changes to the list
  (`lifecycle.ignore_changes` on `azuread_application_redirect_uris.staging`).

**How `ghstg` gets that access:**
- It holds the Microsoft Graph application permission `Application.ReadWrite.OwnedBy`.
- It's an owner of `app-<key>-staging`, so OwnedBy reaches that one app registration and no other.
- `ghprod` has nothing in Graph.
- OwnedBy would also let `ghstg` create new app registrations, which it would then own. Revisit if Entra adds a
  narrower permission.

Applying the Graph assignment is admin consent, so it needs a Privileged Role Administrator or Global Administrator
signed in.

## Placeholder image and port

Both apps start on `mcr.microsoft.com/k8se/quickstart:latest` (port 80), so they exist before the site is built.
Deploys replace the image and Terraform ignores it. Set `target_port = 3000` in the module block before the first
Next.js deploy. The port applies to every revision, so the placeholder stops answering once it changes.

## Custom domains

The provider can create a managed certificate and a hostname, but can't attach one to the other. Bind each domain
with `az`, then import both resources. With TXT validation this works before DNS points at the app, so the switch has
no certificate errors, even with the domain still bound to an old app elsewhere (tested 2026-11-17):

1. At the registrar: `asuid.<host>` TXT with output `custom_domain_verification_id` (alongside any old value).
2. `az containerapp hostname add --hostname <host> -n <production app> -g <rg>`
3. `az containerapp env certificate create -g <rg> -n <environment> --hostname <host> --validation-method TXT
   --certificate-name mc-<host with dots as dashes>`, then a `_dnsauth.<host>` TXT record with the certificate's
   `validationToken`. It's issued in a few minutes.
4. `az containerapp hostname bind --hostname <host> -n <production app> -g <rg> --environment <environment>
   --certificate <name> --validation-method TXT`
5. Switch the A record (apex, to `environment_static_ip`) or CNAME (subdomain, to the app's hostname).
6. Add the host to `custom_domains` and import both resources:

```hcl
import {
  to = module.site.azurerm_container_app_environment_managed_certificate.production["www.example.com"]
  id = "<environment id>/managedCertificates/mc-www-example-com"
}
import {
  to = module.site.azurerm_container_app_custom_domain.production["www.example.com"]
  id = "<production app id>/customDomainName/www.example.com"
}
```

The certificates have `prevent_destroy`: removing a domain is a deliberate `state rm` and an `az` unbind.

## Removing a customer

The storage account, both containers and the portal tables have `lifecycle { prevent_destroy = true }`, so deleting
the module block fails at plan instead of deleting the customer's photos and portal data. A caller can't change that
from outside the module. To remove a customer on purpose:

1. Export or hand over anything in `portfolio`, `portal` and the portal tables that should be kept.
2. `terraform state rm` the storage account, its containers and tables, then delete the module block and plan. Check
   the plan destroys only that customer's resources, and apply.
3. Delete the storage account by hand once nothing in it is needed.
