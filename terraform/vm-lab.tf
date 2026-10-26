
resource "azurerm_virtual_network" "lab" {
  name                = "vnet-clog-dev"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
}

resource "azurerm_subnet" "lab" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.logging.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_network_interface" "lab" {
  name                = "nic-clog-dev"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "lab" {
  name                = "vm-clog-dev"
  resource_group_name = azurerm_resource_group.logging.name
  location            = azurerm_resource_group.logging.location

  size           = var.vm_size
  admin_username = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.lab.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_virtual_machine_extension" "lab_ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.lab.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
}

resource "azurerm_monitor_data_collection_rule_association" "lab" {
  name                    = "assoc-linux-logs"
  target_resource_id      = azurerm_linux_virtual_machine.lab.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux[0].id

  depends_on = [
    azurerm_virtual_machine_extension.lab_ama
  ]
}
