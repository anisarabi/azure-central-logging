terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
  # Production: configure an Azure Storage backend using terraform init -backend-config=...
  backend "local" {
    path = "terraform.tfstate"
  }
}
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
