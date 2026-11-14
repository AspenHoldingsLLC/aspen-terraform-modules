# github-oidc-deployer

An app registration and service principal that GitHub Actions signs in as through OIDC. It has no secret and no
certificate. The only way in is a token from GitHub with one of the subjects you list.

## What it creates

- An app registration, single tenant, with optional owners.
- Its service principal.
- One federated credential per entry in `github_subjects`.
- One Microsoft Graph application permission per entry in `graph_app_roles`, granted (admin consent).

It grants no Azure roles. The landing zone assigns them once a subscription exists, as narrowly as it can.

## Who can apply it

An Azure CLI sign-in by a Global Administrator or Privileged Role Administrator. The CLI's Graph token carries
`Application.ReadWrite.All` and `AppRoleAssignment.ReadWrite.All`, which is all this module needs. Granting a Graph
application permission is admin consent, which is why the role matters.

## Usage

```hcl
module "deployer" {
  source = "git::https://github.com/AspenHoldingsLLC/aspen-terraform-modules.git//modules/github-oidc-deployer?ref=v0.1.0"

  display_name = "app-<client>-terraform"
  notes        = "Terraform deployer for <org>/<repo>."

  github_subjects = {
    production = "repo:<org>@<org id>/<repo>@<repo id>:environment:production"
  }

  graph_app_roles  = ["Policy.Read.All", "Policy.ReadWrite.Authorization"]
  owner_object_ids = [local.operator_object_id]
}
```

Get the subject prefix from GitHub. New repos use the immutable form with numeric IDs:

```bash
gh api repos/<org>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
```

Then add the context: `:environment:<name>`, `:ref:refs/heads/main` or `:pull_request`. An environment is the
narrowest: protect it so only `main` can deploy to it.

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `display_name` | string | | Required |
| `github_subjects` | map(string) | | Required. Name to subject, each starting `repo:` |
| `graph_app_roles` | set(string) | `[]` | Graph permission values. An unknown value fails at plan |
| `owner_object_ids` | set(string) | `[]` | Users who own the app and service principal |
| `notes` | string | `null` | Say which repo manages it |
| `issuer` | string | GitHub.com | Change only for GitHub Enterprise Server |
| `audience` | string | `api://AzureADTokenExchange` | |

## Outputs

- `client_id`: set it as `ARM_CLIENT_ID` in the workflow. It isn't a secret.
- `service_principal_object_id`: the principal for Azure role assignments.
- `application_object_id` and `graph_app_roles`.

## Keep the permissions small

Every Graph permission listed here can be used by any workflow run that matches a subject. Grant only what the
landing zone's layers need, and add a permission in the same pull request as the resource that needs it.
`RoleManagement.ReadWrite.Directory` and `Application.ReadWrite.All` each let the principal make itself Global
Administrator, so think twice before granting either.
