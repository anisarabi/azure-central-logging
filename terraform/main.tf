//central logging terraform module
data "azurerm_client_config" "current" {}

//generate suffix for resource names to avoid collisions in shared environments
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
//centralize the naming and tagging of resources
locals {
  base      = "${var.prefix}-${var.environment}-${random_string.suffix.result}"
  tags      = merge({ managed_by = "terraform", environment = var.environment, service = "central-logging" }, var.tags)
  hub_names = { vm = "eh-vm-logs", apps = "eh-app-logs", platform = "eh-platform-logs", activity = "eh-activity-logs" }
}
//create a resource group for the logging resources
resource "azurerm_resource_group" "logging" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
//create an event hub namespace and event hubs for the different log streams
resource "azurerm_eventhub_namespace" "logging" {
  name                          = "evhns-${local.base}"
  location                      = azurerm_resource_group.logging.location
  resource_group_name           = azurerm_resource_group.logging.name
  sku                           = "Standard"
  capacity                      = var.eventhub_capacity
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true # Demo: harden via private endpoints/network rules in production
  tags                          = local.tags
}
// create event hubs for the different log streams
resource "azurerm_eventhub" "logs" {
  for_each          = local.hub_names
  name              = each.value
  namespace_id      = azurerm_eventhub_namespace.logging.id
  partition_count   = var.eventhub_partitions
  message_retention = var.eventhub_retention_days
}

# allow the azure monitor diagnostic settings to send logs to the event hubs
resource "azurerm_eventhub_namespace_authorization_rule" "monitor" {
  name                = "azure-monitor-diagnostics"
  namespace_name      = azurerm_eventhub_namespace.logging.name
  resource_group_name = azurerm_resource_group.logging.name
  listen              = true
  send                = true
  manage              = true
}

//create SAS rules for the event hubs to allow consumers to read from them
resource "azurerm_eventhub_authorization_rule" "consumer" {
  for_each            = azurerm_eventhub.logs
  name                = "consumer-readonly"
  eventhub_name       = each.value.name
  namespace_name      = azurerm_eventhub_namespace.logging.name
  resource_group_name = azurerm_resource_group.logging.name
  listen              = true
  send                = false
  manage              = false
}

//create a diagnostic setting to send activity logs to the event hub
resource "azurerm_monitor_diagnostic_setting" "activity" {
  name               = "diag-activity-to-eventhub"
  target_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  eventhub_name      = azurerm_eventhub.logs["activity"].name
  eventhub_authorization_rule_id = (
    azurerm_eventhub_namespace_authorization_rule.monitor.id
  )
  enabled_log {
    category = "Administrative"
  }
  enabled_log {
    category = "Security"
  }
  enabled_log {
    category = "Policy"
  }
}
//create a log analytics workspace with 30 days retention to collect logs from the VMs and other resources
resource "azurerm_log_analytics_workspace" "logging" {
  count               = var.enable_vm_pipeline ? 1 : 0
  name                = "law-${local.base}"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

//collect the event Syslog linux
resource "azurerm_monitor_data_collection_rule" "linux" {
  count               = var.enable_vm_pipeline ? 1 : 0
  name                = "dcr-linux-${local.base}"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
  kind                = "Linux"
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.logging[0].id
      name                  = "law"
    }
  }
  data_sources {
    syslog {
      name           = "linux-syslog"
      facility_names = ["auth", "authpriv", "daemon", "syslog", "user", "local0"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
  }
  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law"]
  }
  tags = local.tags
}

// collect the windows event logs
resource "azurerm_monitor_data_collection_rule" "windows" {
  count               = var.enable_vm_pipeline ? 1 : 0
  name                = "dcr-windows-${local.base}"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
  kind                = "Windows"
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.logging[0].id
      name                  = "law"
    }
  }
  data_sources {
    windows_event_log {
      name           = "windows-events"
      streams        = ["Microsoft-Event"]
      x_path_queries = ["Application!*[System[(Level=1 or Level=2 or Level=3)]]", "System!*[System[(Level=1 or Level=2 or Level=3)]]"]
    }
  }
  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["law"]
  }
  tags = local.tags
}

//install azure monitor Agent in the existing VMs
resource "azurerm_virtual_machine_extension" "linux_ama" {
  for_each                   = var.enable_vm_pipeline ? var.linux_vm_ids : {}
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

//install azure monitor Agent in the existing VMs
resource "azurerm_virtual_machine_extension" "windows_ama" {
  for_each                   = var.enable_vm_pipeline ? var.windows_vm_ids : {}
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

//associate the windows VMs with the data collection rules
resource "azurerm_monitor_data_collection_rule_association" "linux" {
  for_each                = var.enable_vm_pipeline ? var.linux_vm_ids : {}
  name                    = "assoc-linux-logs"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux[0].id
  depends_on              = [azurerm_virtual_machine_extension.linux_ama]
}

//associate the windows VMs with the data collection rules
resource "azurerm_monitor_data_collection_rule_association" "windows" {
  for_each                = var.enable_vm_pipeline ? var.windows_vm_ids : {}
  name                    = "assoc-windows-logs"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows[0].id
  depends_on              = [azurerm_virtual_machine_extension.windows_ama]
}

//export Syslog and event to event hub 
resource "azurerm_log_analytics_data_export_rule" "vm" {
  count               = var.enable_vm_pipeline ? 1 : 0
  name                = "export-vm-to-eventhub"
  resource_group_name = azurerm_resource_group.logging.name
  workspace_resource_id = (
    azurerm_log_analytics_workspace.logging[0].id
  )
  destination_resource_id = (
    azurerm_eventhub.logs["vm"].id
  )
  table_names = ["Syslog", "Event"]
  enabled     = true
}
