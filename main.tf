terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "learn-rg" {
  name     = "learn-rg"
  location = "West Europe"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "learn-vn" {
  name                = "learn-vn"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.0.0.0/16"]
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "learn-subnet" {
  name                 = "learn-subnet"
  resource_group_name  = azurerm_resource_group.learn-rg.name
  virtual_network_name = azurerm_virtual_network.learn-vn.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "learn-sg" {
  name                = "learn-sg"
  location            = azurerm_resource_group.learn-rg.location
  resource_group_name = azurerm_resource_group.learn-rg.name
  tags = {
      environment = "dev"
    }
}

resource "azurerm_network_security_rule" "learn-dev-rule" {
  name                        = "learn-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*" //TCP
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*" // Your IP Address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.learn-rg.name
  network_security_group_name = azurerm_network_security_group.learn-sg.name
}

resource "azurerm_subnet_network_security_group_association" "learn-sga" {
  subnet_id                 = azurerm_subnet.learn-subnet.id
  network_security_group_id = azurerm_network_security_group.learn-sg.id
}

resource "azurerm_public_ip" "learn-ip" {
  name                = "learn-ip"
  resource_group_name = azurerm_resource_group.learn-rg.name
  location            = azurerm_resource_group.learn-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "learn-nic" {
  name                = "learn-nic"
  location            = azurerm_resource_group.learn-rg.location
  resource_group_name = azurerm_resource_group.learn-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.learn-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.learn-ip.id
  }

   tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "learn-vm" {
  name                = "learn-vm"
  resource_group_name = azurerm_resource_group.learn-rg.name
  location            = azurerm_resource_group.learn-rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.learn-nic.id,
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/learnazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname = self.public_ip_address
      user = "adminuser"
      identityfile = "~/.ssh/learnazurekey"
    })
    interpreter = var.host_os == "linux" ? ["bash", "-c"] : ["Powershell", "-Command"]
  }

   tags = {
    environment = "dev"
  }
}

data "azure_public_ip" "learn-ip-data"{
  name = azure_public_ip.learn-ip.name
  resource_group_name = azurerm_resource_group.learn-rg.name
}

output public_ip_address {
  value       = "${azurerm_linux_virtual_machine.learn-vm.name}: ${data.azure_public_ip.learn-ip.data.ip_address}"
  sensitive   = false
  description = "showcase public ip"
}
