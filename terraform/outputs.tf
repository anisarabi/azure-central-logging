output "resource_group_name" { value = azurerm_resource_group.logging.name }
output "eventhub_namespace_name" { value = azurerm_eventhub_namespace.logging.name }
output "eventhub_names" { value = { for k, v in azurerm_eventhub.logs : k => v.name } }
output "log_analytics_workspace_id" { value = var.enable_vm_pipeline ? azurerm_log_analytics_workspace.logging[0].id : null }
output "monitor_sas_rule_id" { value = azurerm_eventhub_namespace_authorization_rule.monitor.id }
