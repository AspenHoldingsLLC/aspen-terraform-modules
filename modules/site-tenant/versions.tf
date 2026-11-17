terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.10, < 6.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.13, < 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.9, < 4.0"
    }
  }
}
