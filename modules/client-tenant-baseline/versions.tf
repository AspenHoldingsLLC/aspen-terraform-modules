terraform {
  required_version = ">= 1.9"

  required_providers {
    msgraph = {
      source  = "Microsoft/msgraph"
      version = ">= 0.6.0, < 1.0.0"
    }
  }
}
