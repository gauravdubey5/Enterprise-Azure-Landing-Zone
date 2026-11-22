# Production Environment Configuration - All values in nested maps and objects

project_name   = "gd-ent"
environment    = "prod"
location       = "eastus"
location_short = "eus"
owner          = "CloudPlatformTeam"
cost_center    = "CC-PROD-PLATFORM"
criticality    = "Tier-1-Mission-Critical"

admin_username       = "azureuser"
admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGX8a5dF+p1k93VqM5yL01bZl81234567890abcdefgh enterprise-admin@company.com"

# 1. Resource Groups Nested Map
resource_groups = {
  hub = {
    name_suffix = "hub-rg"
  }
  spoke = {
    name_suffix = "spoke-rg"
  }
  data = {
    name_suffix = "data-rg"
  }
}

# 2. Virtual Networks & Subnets Nested Map
networks = {
  hub = {
    name_suffix   = "hub-vnet"
    rg_key        = "hub"
    address_space = ["10.0.0.0/16"]
    subnets = {
      AzureFirewallSubnet = {
        address_prefixes = ["10.0.1.0/26"]
      }
      AzureFirewallManagementSubnet = {
        address_prefixes = ["10.0.1.64/26"]
      }
      AzureBastionSubnet = {
        address_prefixes = ["10.0.2.0/26"]
      }
      GatewaySubnet = {
        address_prefixes = ["10.0.3.0/27"]
      }
      InboundDnsResolverSubnet = {
        address_prefixes = ["10.0.4.0/28"]
        delegations = [{
          name = "Microsoft.Network.dnsResolvers"
          service_delegation = {
            name    = "Microsoft.Network/dnsResolvers"
            actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
          }
        }]
      }
      OutboundDnsResolverSubnet = {
        address_prefixes = ["10.0.4.16/28"]
        delegations = [{
          name = "Microsoft.Network.dnsResolvers"
          service_delegation = {
            name    = "Microsoft.Network/dnsResolvers"
            actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
          }
        }]
      }
      SharedServicesSubnet = {
        address_prefixes  = ["10.0.5.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
    }
  }

  spoke = {
    name_suffix   = "spoke-vnet"
    rg_key        = "spoke"
    address_space = ["10.1.0.0/16"]
    subnets = {
      AppGatewaySubnet = {
        address_prefixes = ["10.1.1.0/24"]
      }
      FrontendSubnet = {
        address_prefixes  = ["10.1.2.0/24"]
        service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
      }
      InternalLbSubnet = {
        address_prefixes = ["10.1.3.0/24"]
      }
      BackendSubnet = {
        address_prefixes  = ["10.1.4.0/24"]
        service_endpoints = ["Microsoft.Sql", "Microsoft.Storage", "Microsoft.KeyVault"]
      }
      PrivateEndpointSubnet = {
        address_prefixes                  = ["10.1.5.0/24"]
        private_endpoint_network_policies = "Disabled"
      }
    }
  }
}

# 3. Route Tables Nested Map
route_tables = {
  appgw = {
    name_suffix = "appgw-rt"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "AppGatewaySubnet"
    routes = [
      {
        name           = "Direct-Internet-Ingress"
        address_prefix = "0.0.0.0/0"
        next_hop_type  = "Internet"
      }
    ]
  }
  frontend = {
    name_suffix = "frontend-rt"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "FrontendSubnet"
    routes = [
      {
        name                 = "Egress-Via-Hub-Firewall"
        address_prefix       = "0.0.0.0/0"
        next_hop_type        = "VirtualAppliance"
        next_hop_to_firewall = true
      }
    ]
  }
  backend = {
    name_suffix = "backend-rt"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "BackendSubnet"
    routes = [
      {
        name                 = "Egress-Via-Hub-Firewall"
        address_prefix       = "0.0.0.0/0"
        next_hop_type        = "VirtualAppliance"
        next_hop_to_firewall = true
      }
    ]
  }
}

# 4. Network Security Groups Nested Map
network_security_groups = {
  appgw = {
    name_suffix = "appgw-nsg"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "AppGatewaySubnet"
    security_rules = [
      {
        name                       = "Allow-HTTP-Inbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
        description                = "Allow HTTP ingress traffic from Internet"
      },
      {
        name                       = "Allow-HTTPS-Inbound"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
        description                = "Allow HTTPS ingress traffic from Internet"
      },
      {
        name                       = "Allow-GatewayManager-Inbound"
        priority                   = 120
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "65200-65535"
        source_address_prefix      = "GatewayManager"
        destination_address_prefix = "*"
        description                = "Required for Azure Application Gateway v2 control plane"
      },
      {
        name                       = "Allow-AzureLoadBalancer-Inbound"
        priority                   = 130
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "AzureLoadBalancer"
        destination_address_prefix = "*"
        description                = "Allow health probe from Azure Load Balancer"
      }
    ]
  }

  frontend = {
    name_suffix = "frontend-nsg"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "FrontendSubnet"
    security_rules = [
      {
        name                       = "Allow-Traffic-From-AppGateway"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "10.1.1.0/24"
        destination_address_prefix = "10.1.2.0/24"
        description                = "Allow traffic from App Gateway subnet only"
      },
      {
        name                       = "Allow-Bastion-SSH-Inbound"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "10.0.2.0/26"
        destination_address_prefix = "10.1.2.0/24"
        description                = "Allow SSH management from Azure Bastion Subnet only"
      },
      {
        name                       = "Deny-All-Other-Inbound"
        priority                   = 4096
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
        description                = "Default deny all other inbound traffic"
      }
    ]
  }

  internal_lb = {
    name_suffix = "ilb-nsg"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "InternalLbSubnet"
    security_rules = [
      {
        name                       = "Allow-Frontend-To-ILB"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "8080"
        source_address_prefix      = "10.1.2.0/24"
        destination_address_prefix = "10.1.3.0/24"
        description                = "Allow traffic from Frontend VMSS to ILB"
      },
      {
        name                       = "Allow-AzureLoadBalancer-Probe"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "AzureLoadBalancer"
        destination_address_prefix = "*"
        description                = "Allow Azure Load Balancer health check probes"
      }
    ]
  }

  backend = {
    name_suffix = "backend-nsg"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "BackendSubnet"
    security_rules = [
      {
        name                       = "Allow-Traffic-From-ILB"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "8080"
        source_address_prefix      = "10.1.3.0/24"
        destination_address_prefix = "10.1.4.0/24"
        description                = "Allow traffic from Internal Load Balancer only"
      },
      {
        name                       = "Allow-Bastion-SSH-Inbound"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "10.0.2.0/26"
        destination_address_prefix = "10.1.4.0/24"
        description                = "Allow SSH management from Azure Bastion Subnet only"
      },
      {
        name                       = "Deny-All-Other-Inbound"
        priority                   = 4096
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
        description                = "Default deny all other inbound traffic"
      }
    ]
  }

  pe = {
    name_suffix = "pe-nsg"
    rg_key      = "spoke"
    vnet_key    = "spoke"
    subnet_key  = "PrivateEndpointSubnet"
    security_rules = [
      {
        name                       = "Allow-Backend-To-PE"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["443", "1433", "6380"]
        source_address_prefix      = "10.1.4.0/24"
        destination_address_prefix = "10.1.5.0/24"
        description                = "Allow database and storage calls from Backend VMSS"
      },
      {
        name                       = "Deny-All-Other-Inbound"
        priority                   = 4096
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
        description                = "Deny direct public internet access to private endpoints"
      }
    ]
  }
}

# 5. Linux VMSS Compute Nested Map
vms = {
  frontend = {
    name_suffix     = "fe-vmss"
    rg_key          = "spoke"
    vnet_key        = "spoke"
    subnet_key      = "FrontendSubnet"
    sku             = "Standard_D2s_v5"
    instances       = 2
    min_instances   = 2
    max_instances   = 10
    zones           = ["1", "2", "3"]
    target_balancer = "appgw"
  }
  backend = {
    name_suffix     = "be-vmss"
    rg_key          = "spoke"
    vnet_key        = "spoke"
    subnet_key      = "BackendSubnet"
    sku             = "Standard_D2s_v5"
    instances       = 2
    min_instances   = 2
    max_instances   = 10
    zones           = ["1", "2", "3"]
    target_balancer = "ilb"
  }
}

# 6. Private DNS Zones
private_dns_zones = [
  "privatelink.database.windows.net",
  "privatelink.blob.core.windows.net",
  "privatelink.vaultcore.azure.net",
  "privatelink.documents.azure.com",
  "privatelink.redis.cache.windows.net"
]

enable_private_endpoints = true

# 7. Private Endpoints Nested Map
private_endpoints = {
  key_vault = {
    name_suffix       = "kv-pe"
    rg_key            = "spoke"
    vnet_key          = "spoke"
    subnet_key        = "PrivateEndpointSubnet"
    target_type       = "key_vault"
    subresource_names = ["vault"]
    dns_zone_name     = "privatelink.vaultcore.azure.net"
  }
  storage = {
    name_suffix       = "sa-pe"
    rg_key            = "spoke"
    vnet_key          = "spoke"
    subnet_key        = "PrivateEndpointSubnet"
    target_type       = "storage"
    subresource_names = ["blob"]
    dns_zone_name     = "privatelink.blob.core.windows.net"
  }
  sql = {
    name_suffix       = "sql-pe"
    rg_key            = "spoke"
    vnet_key          = "spoke"
    subnet_key        = "PrivateEndpointSubnet"
    target_type       = "sql"
    subresource_names = ["sqlServer"]
    dns_zone_name     = "privatelink.database.windows.net"
  }
  cosmos = {
    name_suffix       = "cosmos-pe"
    rg_key            = "spoke"
    vnet_key          = "spoke"
    subnet_key        = "PrivateEndpointSubnet"
    target_type       = "cosmos"
    subresource_names = ["Sql"]
    dns_zone_name     = "privatelink.documents.azure.com"
  }
  redis = {
    name_suffix       = "redis-pe"
    rg_key            = "spoke"
    vnet_key          = "spoke"
    subnet_key        = "PrivateEndpointSubnet"
    target_type       = "redis"
    subresource_names = ["redisCache"]
    dns_zone_name     = "privatelink.redis.cache.windows.net"
  }
}

# 8. Structured Service Objects
firewall = {
  enabled           = true
  sku_tier          = "Premium"
  threat_intel_mode = "Alert"
  zones             = ["1", "2", "3"]
}

bastion = {
  enabled = true
  sku     = "Standard"
  zones   = ["1", "2", "3"]
}

vpn_gateway = {
  enabled       = true
  sku           = "VpnGw2AZ"
  active_active = true
  enable_bgp    = false
  zones         = ["1", "2", "3"]
}

dns_resolver = {
  enabled          = true
  forwarding_rules = {}
}

application_gateway = {
  enabled           = true
  waf_mode          = "Prevention"
  min_capacity      = 2
  max_capacity      = 10
  zones             = ["1", "2", "3"]
  backend_port      = 80
  health_probe_path = "/healthz"
}

internal_lb = {
  frontend_port  = 8080
  backend_port   = 8080
  probe_protocol = "Http"
  probe_path     = "/healthz"
  zones          = ["1", "2", "3"]
}

sql_database = {
  sku_name       = "GP_Gen5_2"
  zone_redundant = true
  max_size_gb    = 32
  admin_username = "sqladminuser"
  admin_password = "P@ssw0rdEnterprise2026!#Strong"
}

cosmos_db = {
  enabled        = true
  zone_redundant = true
}

redis = {
  enabled  = true
  sku_name = "Premium"
  family   = "P"
  capacity = 1
  zones    = ["1", "2"]
}

monitoring = {
  retention_in_days  = 30
  alert_email        = "platform-sre@company.com"
  enable_vmss_alert  = true
  enable_appgw_alert = true
}

backup = {
  enabled               = true
  storage_mode_type     = "GeoRedundant"
  retention_daily_count = 30
}
