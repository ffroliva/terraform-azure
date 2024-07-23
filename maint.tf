# Running a docker container in Azure private virtual network (vnet) with public access
# The container must be in a manually created vnet if you want to do peering to another
# private network. In this config the subnet gives permission to use blob storage for
# the containe group.
#
# Public IP - Load balancer - Backend pool ---- vnet
#                   |             |              |
#                LB rule          |           subnet ----- Container group - Docker app 
#                   |             |              |                               |
#                 Probe           |        Security Group                        |
#                                 |                                              |
#                                 └----------------------------------------------┘

terraform {

  required_providers {

    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.113.0"
    }

    random = {
      source = "hashicorp/random"
      version = "3.6.2"
    }
  }
}

provider "azurerm" {
  features {
    
  }
}

provider "random" {
  
}

resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}

# VNet Definition
resource "azurerm_virtual_network" "proxy" {
  name                = "proxynetwork${random_pet.rg_name.id}"
  address_space       = ["10.10.0.0/24"]
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_subnet" "proxy" {
  name                 = "proxysubnet${random_pet.rg_name.id}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.proxy.name
  address_prefixes     = ["10.10.0.0/25"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name      = "acidelegationservice"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_public_ip" "proxy" {
  name                = "proxy-publicip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  domain_name_label   = "rcl-cabei-test-proxy-domain"               # Change this!
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "proxy" {
  name                = "proxy-lb"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "publicIPAddress"
    public_ip_address_id = azurerm_public_ip.proxy.id
  }
}

resource "azurerm_lb_backend_address_pool" "proxy" {
  loadbalancer_id = azurerm_lb.proxy.id
  name            = "proxy-pool"
}

resource "azurerm_lb_probe" "http_probe" {
  loadbalancer_id  = azurerm_lb.proxy.id
  name             = "http"
  port             = 80
  protocol         = "Http"
  request_path     = "/"
}

# Duplicate following two blocks and change to 443/https for secure traffic

resource "azurerm_lb_rule" "proxy_80" {
  loadbalancer_id                = azurerm_lb.proxy.id
  name                           = "HTTP"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "publicIPAddress"
  probe_id                       = azurerm_lb_probe.http_probe.id
  backend_address_pool_ids       = [ azurerm_lb_backend_address_pool.proxy.id ]
  disable_outbound_snat          = true
}

resource "azurerm_network_security_group" "proxy" {
  name                = "allowInternetzTraffic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "allow_http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    destination_port_range     = "80"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "proxy" {
  subnet_id                 = azurerm_subnet.proxy.id
  network_security_group_id = azurerm_network_security_group.proxy.id
}

# This is ONE node behind a load balancer. 
# Duplicate following two blocks if you want load balancing with more than one node

# Container Creation
resource "azurerm_container_group" "hello" {
  name                = "hello-${random_pet.rg_name.id}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  ip_address_type     = "Private"
  os_type             = "Linux"
  restart_policy      = "Always"
  subnet_ids          = [azurerm_subnet.proxy.id]
  

  container {
    name   = "test-test-hello"
    image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
    cpu    = 1
    memory = 1

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}

# Loadbalancer Backend Pool Association
resource "azurerm_lb_backend_address_pool_address" "container-1" {
  name                    = "container-1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.proxy.id
  virtual_network_id      = azurerm_virtual_network.proxy.id
  ip_address              = azurerm_container_group.hello.ip_address

}