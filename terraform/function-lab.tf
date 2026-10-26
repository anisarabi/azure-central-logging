resource "azurerm_storage_account" "function_lab" {
  count                    = var.enable_function_lab ? 1 : 0
  name                     = "stclog${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.logging.name
  location                 = azurerm_resource_group.logging.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_service_plan" "function_lab" {
  count               = var.enable_function_lab ? 1 : 0
  name                = "asp-func-${local.base}"
  resource_group_name = azurerm_resource_group.logging.name
  location            = azurerm_resource_group.logging.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "lab" {
  count                       = var.enable_function_lab ? 1 : 0
  name                        = "func-${local.base}"
  resource_group_name         = azurerm_resource_group.logging.name
  location                    = azurerm_resource_group.logging.location
  service_plan_id             = azurerm_service_plan.function_lab[0].id
  storage_account_name        = azurerm_storage_account.function_lab[0].name
  storage_account_access_key  = azurerm_storage_account.function_lab[0].primary_access_key
  https_only                  = true
  functions_extension_version = "~4"

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
  }
}

resource "azurerm_monitor_diagnostic_setting" "function_lab" {
  count                          = var.enable_function_lab && var.enable_function_diagnostics ? 1 : 0
  name                           = "diag-function-to-eventhub"
  target_resource_id             = azurerm_linux_function_app.lab[0].id
  eventhub_name                  = azurerm_eventhub.logs["apps"].name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.monitor.id

  enabled_log {
    category = "FunctionAppLogs"
  }
}

output "function_lab_name" {
  value = var.enable_function_lab ? azurerm_linux_function_app.lab[0].name : null
}