# Production Environment - variables.tf

variable "project_name" {
  type        = string
  description = "Project name prefix for resources"
  default     = "gd-ent"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
  default     = "prod"
}

variable "location" {
  type        = string
  description = "Azure Region for infrastructure deployment"
  default     = "eastus"
}

variable "location_short" {
  type        = string
  description = "Short name for Azure Region (e.g. eus, wus2)"
  default     = "eus"
}

variable "owner" {
  type        = string
  description = "Owner of the deployment"
  default     = "CloudPlatformTeam"
}

variable "cost_center" {
  type        = string
  description = "Cost center for billing allocation"
  default     = "CC-PROD-PLATFORM"
}

variable "criticality" {
  type        = string
  description = "Workload criticality rating"
  default     = "Tier-1-Mission-Critical"
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags to merge with default tags"
  default     = {}
}

variable "admin_username" {
  type        = string
  description = "Administrator username for Linux VMs"
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH Public Key for Linux VMSS instances"
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGX8a5dF+p1k93VqM5yL01bZl81234567890abcdefgh enterprise-admin@company.com"
}

# ==============================================================================
# NESTED MAP CONFIGURATIONS
# ==============================================================================

variable "resource_groups" {
  type = map(object({
    name_suffix = string
    location    = optional(string)
    tags        = optional(map(string), {})
  }))
  description = "Nested map of Resource Groups to create"
}

variable "networks" {
  type = map(object({
    name_suffix   = string
    rg_key        = string
    address_space = list(string)
    subnets = map(object({
      address_prefixes                  = list(string)
      service_endpoints                 = optional(list(string), [])
      private_endpoint_network_policies = optional(string, "Disabled")
      delegations = optional(list(object({
        name = string
        service_delegation = object({
          name    = string
          actions = optional(list(string))
        })
      })), [])
    }))
  }))
  description = "Nested map of Virtual Networks and their dedicated Subnets"
}

variable "route_tables" {
  type = map(object({
    name_suffix = string
    rg_key      = string
    vnet_key    = string
    subnet_key  = string
    routes = list(object({
      name                   = string
      address_prefix         = string
      next_hop_type          = string
      next_hop_to_firewall   = optional(bool, false)
      next_hop_in_ip_address = optional(string)
    }))
  }))
  description = "Nested map of Route Tables and custom UDR rules"
}

variable "network_security_groups" {
  type = map(object({
    name_suffix = string
    rg_key      = string
    vnet_key    = string
    subnet_key  = string
    security_rules = list(object({
      name                         = string
      priority                     = number
      direction                    = string
      access                       = string
      protocol                     = string
      source_port_range            = optional(string)
      source_port_ranges           = optional(list(string))
      destination_port_range       = optional(string)
      destination_port_ranges      = optional(list(string))
      source_address_prefix        = optional(string)
      source_address_prefixes      = optional(list(string))
      destination_address_prefix   = optional(string)
      destination_address_prefixes = optional(list(string))
      description                  = optional(string)
    }))
  }))
  description = "Nested map of Network Security Groups and associated security rules"
}

variable "vms" {
  type = map(object({
    name_suffix     = string
    rg_key          = string
    vnet_key        = string
    subnet_key      = string
    sku             = string
    instances       = number
    min_instances   = optional(number, 2)
    max_instances   = optional(number, 10)
    zones           = list(string)
    target_balancer = string # "appgw", "ilb", or "none"
  }))
  description = "Nested map of Linux Virtual Machine Scale Sets"
}

variable "private_dns_zones" {
  type        = list(string)
  description = "List of Azure PaaS Private DNS zones"
}

variable "enable_private_endpoints" {
  type        = bool
  description = "Global switch to enable private endpoints"
  default     = true
}

variable "private_endpoints" {
  type = map(object({
    name_suffix       = string
    rg_key            = string
    vnet_key          = string
    subnet_key        = string
    target_type       = string # "key_vault", "storage", "sql", "cosmos", "redis"
    subresource_names = list(string)
    dns_zone_name     = string
  }))
  description = "Nested map of Private Endpoints configuration"
}

# ==============================================================================
# STRUCTURED SERVICE OBJECTS
# ==============================================================================

variable "firewall" {
  type = object({
    enabled           = bool
    sku_tier          = string
    threat_intel_mode = string
    zones             = list(string)
  })
  description = "Azure Firewall configuration object"
}

variable "bastion" {
  type = object({
    enabled = bool
    sku     = string
    zones   = list(string)
  })
  description = "Azure Bastion configuration object"
}

variable "vpn_gateway" {
  type = object({
    enabled       = bool
    sku           = string
    active_active = bool
    enable_bgp    = bool
    zones         = list(string)
  })
  description = "VPN Gateway configuration object"
}

variable "dns_resolver" {
  type = object({
    enabled = bool
    forwarding_rules = optional(map(object({
      domain_name = string
      enabled     = optional(bool, true)
      target_dns_servers = list(object({
        ip_address = string
        port       = optional(number, 53)
      }))
    })), {})
  })
  description = "Azure DNS Private Resolver configuration object"
}

variable "application_gateway" {
  type = object({
    enabled           = bool
    waf_mode          = string
    min_capacity      = number
    max_capacity      = number
    zones             = list(string)
    backend_port      = number
    health_probe_path = string
  })
  description = "Application Gateway WAF_v2 configuration object"
}

variable "internal_lb" {
  type = object({
    frontend_port  = number
    backend_port   = number
    probe_protocol = string
    probe_path     = string
    zones          = list(string)
  })
  description = "Internal Load Balancer configuration object"
}

variable "sql_database" {
  type = object({
    sku_name       = string
    zone_redundant = bool
    max_size_gb    = number
    admin_username = string
    admin_password = string
  })
  description = "Azure SQL Database configuration object"
  sensitive   = true
}

variable "cosmos_db" {
  type = object({
    enabled        = bool
    zone_redundant = bool
  })
  description = "Cosmos DB configuration object"
}

variable "redis" {
  type = object({
    enabled  = bool
    sku_name = string
    family   = string
    capacity = number
    zones    = list(string)
  })
  description = "Azure Cache for Redis configuration object"
}

variable "monitoring" {
  type = object({
    retention_in_days  = number
    alert_email        = string
    enable_vmss_alert  = bool
    enable_appgw_alert = bool
  })
  description = "Azure Monitor & Log Analytics configuration object"
}

variable "backup" {
  type = object({
    enabled               = bool
    storage_mode_type     = string
    retention_daily_count = number
  })
  description = "Recovery Services Vault configuration object"
}
