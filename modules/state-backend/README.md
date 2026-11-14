# state-backend

A storage account and container for Terraform state, in the client's own subscription.

## What it creates

- A resource group, unless `create_resource_group = false`.
- A StorageV2 account, LRS, TLS 1.2, with account keys, SAS and anonymous access off. Only Entra tokens work.
- Blob versioning, plus soft delete for blobs and containers (`retention_days`, 30 by default), so an overwritten or
  deleted state file can be recovered.
- A private container, `tfstate` by default.
- Storage Blob Data Contributor on the account for each principal in `data_contributor_principal_ids`. Owner on the
  subscription doesn't include blob data access, and the azurerm backend needs it.

The account and container have `prevent_destroy`.

## Network access

Public network access stays on, because GitHub-hosted runners and an operator's machine have no fixed address to
allow. Every request still needs an Entra token. Trivy's AZU-0012 is ignored inline with that reason. Put the account
behind a private endpoint if applies move to a self-hosted runner.

## First run

The account holds the state of the layer that creates it, so that layer's first apply uses local state:

```bash
mv backend.tf backend.tf.off
terraform init && terraform plan -out tfplan && terraform apply tfplan
mv backend.tf.off backend.tf
terraform init -migrate-state      # a 403 right after the apply means the role hasn't propagated; wait a minute
rm -f terraform.tfstate terraform.tfstate.backup tfplan
```

A layer that already has state elsewhere, such as an interim container, runs `terraform init -migrate-state` once
after changing its `backend.tf`.

## Usage

```hcl
module "state" {
  source = "git::https://github.com/AspenHoldingsLLC/aspen-terraform-modules.git//modules/state-backend?ref=v0.1.0"

  resource_group_name  = "rgp-terraform-eus2"
  location             = "eastus2"
  storage_account_name = "sta<client>tfstateeus2"

  data_contributor_principal_ids = {
    deployer = module.deployer.service_principal_object_id
    admins   = module.admins.admin_group_object_id
  }
}
```

## Inputs

| Name | Type | Default |
|---|---|---|
| `resource_group_name` | string | |
| `create_resource_group` | bool | `true` |
| `location` | string | |
| `storage_account_name` | string, 3-24 lower-case letters and digits | |
| `container_name` | string | `tfstate` |
| `data_contributor_principal_ids` | map(string) | `{}` |
| `retention_days` | number, 7-365 | `30` |
| `tags` | map(string) | `{}` |

## Outputs

- `backend`: the resource group, account and container for each layer's `backend.tf`.
- `storage_account_id`.
