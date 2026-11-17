# aspen-terraform-modules

Generic Terraform modules for the client tenants Aspen Holdings runs. Each client has its own Entra tenant, GitHub
organization and landing zone repo, and that repo calls these modules at a tag. A client keeps the exact versions it
uses after it leaves Aspen.

## Modules

| Module | What it does | Signs in as |
|---|---|---|
| [`client-tenant-admins`](modules/client-tenant-admins/README.md) | The tenant's admin security group, and a check on its two emergency access accounts | An admin's Azure CLI sign-in |
| [`github-oidc-deployer`](modules/github-oidc-deployer/README.md) | An app registration and service principal that GitHub Actions signs in as through OIDC, with the Graph application permissions it needs | An admin's Azure CLI sign-in, as Global Administrator or Privileged Role Administrator |
| [`client-tenant-baseline`](modules/client-tenant-baseline/README.md) | Tenant-wide settings: who may invite guests, register apps, create tenants and groups, or join by email, and MFA trust for the operator's home tenant | The deployer service principal. An Azure CLI token has no `Policy.*` scopes |
| [`state-backend`](modules/state-backend/README.md) | A storage account and container for Terraform state in the client's own subscription, Entra ID only | Anyone with Owner on the subscription |
| [`site-tenant`](modules/site-tenant/README.md) | A customer's website on Azure Container Apps: production, a staging app behind Entra sign-in with PR previews, blob storage, an optional client portal and AI editor, and GitHub OIDC deploy identities. Its own environment and registry, or shared ones | An admin's Azure CLI sign-in with Owner, as Global Administrator or Privileged Role Administrator |

## Rules for what goes here

- **Generic only.** No tenant or subscription IDs, client names, email addresses or Aspen settings. Those belong in the
  client's landing zone repo. CI fails on any GUID that isn't one of the placeholders the examples use.
- **No secrets in state.** Modules don't create passwords or client secrets. Deployers sign in through OIDC.
- **Version ranges, not pins.** Modules say which provider versions they work with. The landing zone that calls them
  pins exact versions and commits its lock file.
- Every module has a README and an `examples/basic` that CI validates.

## Calling a module

```hcl
module "deployer" {
  source = "git::https://github.com/AspenHoldingsLLC/aspen-terraform-modules.git//modules/github-oidc-deployer?ref=v0.1.0"
  # ...
}
```

Pin a tag, never a branch. A new tag is a new release: read its changes, then bump the `ref` in one landing zone at a
time.

The repo is public, so `terraform init` fetches modules with no token, from any machine or GitHub organization.

## Releases

Tags follow semantic versioning, starting at `v0.1.0`. The maintainer cuts each tag by hand after a merge. Nothing tags
itself.

## CI

`.github/workflows/ci.yml` runs on every pull request: gitleaks, a check for real IDs, `terraform fmt`, `validate` on
each example, tflint with the azurerm ruleset, and Trivy (HIGH and CRITICAL fail). It holds no cloud credentials and
never reaches a tenant. Run the same tools locally before pushing.

## Licence

MIT. See [LICENSE](LICENSE).
