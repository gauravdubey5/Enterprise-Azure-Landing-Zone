terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "random_string" "unique" {
  length  = 5
  special = false
  upper   = false
}

locals {
  name_prefix = "${var.project_name}-${var.environment}-${var.location_short}"
  tags = merge(
    {
      Project      = var.project_name
      Environment  = var.environment
      Owner        = var.owner
      ManagedBy    = "Terraform"
      CostCenter   = var.cost_center
      Criticality  = var.criticality
      Architecture = "Hub-and-Spoke-HA"
    },
    var.extra_tags
  )

  frontend_cloud_init = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    mkdir -p /var/www/html/healthz
    echo "OK-DEV-FRONTEND" > /var/www/html/healthz/index.html
    systemctl restart nginx
  EOF

  backend_cloud_init = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3
    mkdir -p /opt/app
    cat <<'PY' > /opt/app/server.py
import http.server
import socketserver

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/healthz' or self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"healthy","tier":"backend-vmss","env":"dev"}')
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("", 8080), HealthHandler) as httpd:
    httpd.serve_forever()
PY
    cat <<'SVC' > /etc/systemd/system/backend-api.service
[Unit]
Description=Dev Backend API
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/app/server.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload
    systemctl enable backend-api
    systemctl start backend-api
  EOF
}

# Resource Groups (for_each over nested map)
module "resource_groups" {
  for_each = var.resource_groups
  source   = "../../modules/resource-group"
  name     = "${local.name_prefix}-${each.value.name_suffix}"
  location = coalesce(each.value.location, var.location)
  tags     = merge(local.tags, each.value.tags)
}

# Monitoring
module "monitoring" {
  source              = "../../modules/monitoring"
  name                = "${local.name_prefix}-law"
  resource_group_name = module.resource_groups["hub"].name
  location            = module.resource_groups["hub"].location
  retention_in_days   = var.monitoring.retention_in_days
  alert_email         = var.monitoring.alert_email
  enable_vmss_alert   = var.monitoring.enable_vmss_alert
  monitored_vmss_id   = module.vmss["frontend"].id
  enable_appgw_alert  = var.application_gateway.enabled && var.monitoring.enable_appgw_alert
  monitored_appgw_id  = var.application_gateway.enabled ? module.application_gateway[0].id : null
  tags                = local.tags
}

# Virtual Networks & Subnets (for_each over nested map)
module "virtual_networks" {
  for_each            = var.networks
  source              = "../../modules/virtual-network"
  name                = "${local.name_prefix}-${each.value.name_suffix}"
  resource_group_name = module.resource_groups[each.value.rg_key].name
  location            = module.resource_groups[each.value.rg_key].location
  address_space       = each.value.address_space
  tags                = local.tags
}

module "subnets" {
  for_each             = var.networks
  source               = "../../modules/subnet"
  resource_group_name  = module.resource_groups[each.value.rg_key].name
  virtual_network_name = module.virtual_networks[each.key].name
  subnets              = each.value.subnets

  depends_on = [module.virtual_networks]
}

# Gateways
module "firewall" {
  count                      = var.firewall.enabled ? 1 : 0
  source                     = "../../modules/firewall"
  name                       = "${local.name_prefix}-afw"
  resource_group_name        = module.resource_groups["hub"].name
  location                   = module.resource_groups["hub"].location
  subnet_id                  = module.subnets["hub"].subnet_ids["AzureFirewallSubnet"]
  sku_tier                   = var.firewall.sku_tier
  threat_intel_mode          = var.firewall.threat_intel_mode
  zones                      = var.firewall.zones
  log_analytics_workspace_id = module.monitoring.id
  tags                       = local.tags
}

module "bastion" {
  count                      = var.bastion.enabled ? 1 : 0
  source                     = "../../modules/bastion"
  name                       = "${local.name_prefix}-bas"
  resource_group_name        = module.resource_groups["hub"].name
  location                   = module.resource_groups["hub"].location
  subnet_id                  = module.subnets["hub"].subnet_ids["AzureBastionSubnet"]
  sku                        = var.bastion.sku
  zones                      = var.bastion.zones
  log_analytics_workspace_id = module.monitoring.id
  tags                       = local.tags
}

module "vpn_gateway" {
  count                      = var.vpn_gateway.enabled ? 1 : 0
  source                     = "../../modules/vpn-gateway"
  name                       = "${local.name_prefix}-vpngw"
  resource_group_name        = module.resource_groups["hub"].name
  location                   = module.resource_groups["hub"].location
  subnet_id                  = module.subnets["hub"].subnet_ids["GatewaySubnet"]
  sku                        = var.vpn_gateway.sku
  active_active              = var.vpn_gateway.active_active
  enable_bgp                 = var.vpn_gateway.enable_bgp
  zones                      = var.vpn_gateway.zones
  log_analytics_workspace_id = module.monitoring.id
  tags                       = local.tags
}

module "dns_resolver" {
  count                      = var.dns_resolver.enabled ? 1 : 0
  source                     = "../../modules/dns-resolver"
  name                       = "${local.name_prefix}-dnsres"
  resource_group_name        = module.resource_groups["hub"].name
  location                   = module.resource_groups["hub"].location
  virtual_network_id         = module.virtual_networks["hub"].id
  inbound_subnet_id          = module.subnets["hub"].subnet_ids["InboundDnsResolverSubnet"]
  outbound_subnet_id         = module.subnets["hub"].subnet_ids["OutboundDnsResolverSubnet"]
  forwarding_rules           = var.dns_resolver.forwarding_rules
  linked_virtual_network_ids = [module.virtual_networks["spoke"].id]
  tags                       = local.tags
}

# Peering
module "vnet_peering" {
  source                    = "../../modules/vnet-peering"
  hub_resource_group_name   = module.resource_groups["hub"].name
  hub_vnet_name             = module.virtual_networks["hub"].name
  hub_vnet_id               = module.virtual_networks["hub"].id
  spoke_resource_group_name = module.resource_groups["spoke"].name
  spoke_vnet_name           = module.virtual_networks["spoke"].name
  spoke_vnet_id             = module.virtual_networks["spoke"].id
  allow_gateway_transit     = var.vpn_gateway.enabled
  use_remote_gateways       = false

  depends_on = [module.subnets]
}

# Route Tables (for_each over nested map)
module "route_tables" {
  for_each            = var.route_tables
  source              = "../../modules/route-table"
  name                = "${local.name_prefix}-${each.value.name_suffix}"
  resource_group_name = module.resource_groups[each.value.rg_key].name
  location            = module.resource_groups[each.value.rg_key].location
  subnet_ids          = [module.subnets[each.value.vnet_key].subnet_ids[each.value.subnet_key]]
  routes = [
    for r in each.value.routes : {
      name                   = r.name
      address_prefix         = r.address_prefix
      next_hop_type          = r.next_hop_type
      next_hop_in_ip_address = r.next_hop_to_firewall ? (var.firewall.enabled ? module.firewall[0].private_ip : null) : r.next_hop_in_ip_address
    }
  ]
  tags = local.tags
}

# NSGs (for_each over nested map)
module "nsgs" {
  for_each            = var.network_security_groups
  source              = "../../modules/nsg"
  name                = "${local.name_prefix}-${each.value.name_suffix}"
  resource_group_name = module.resource_groups[each.value.rg_key].name
  location            = module.resource_groups[each.value.rg_key].location
  subnet_ids          = [module.subnets[each.value.vnet_key].subnet_ids[each.value.subnet_key]]
  security_rules      = each.value.security_rules
  tags                = local.tags
}

# Load Balancers
module "application_gateway" {
  count                      = var.application_gateway.enabled ? 1 : 0
  source                     = "../../modules/application-gateway"
  name                       = "${local.name_prefix}-appgw"
  resource_group_name        = module.resource_groups["spoke"].name
  location                   = module.resource_groups["spoke"].location
  subnet_id                  = module.subnets["spoke"].subnet_ids["AppGatewaySubnet"]
  waf_mode                   = var.application_gateway.waf_mode
  zones                      = var.application_gateway.zones
  min_capacity               = var.application_gateway.min_capacity
  max_capacity               = var.application_gateway.max_capacity
  backend_port               = var.application_gateway.backend_port
  health_probe_path          = var.application_gateway.health_probe_path
  log_analytics_workspace_id = module.monitoring.id
  tags                       = local.tags
}

module "internal_lb" {
  source                     = "../../modules/internal-load-balancer"
  name                       = "${local.name_prefix}-ilb"
  resource_group_name        = module.resource_groups["spoke"].name
  location                   = module.resource_groups["spoke"].location
  subnet_id                  = module.subnets["spoke"].subnet_ids["InternalLbSubnet"]
  zones                      = var.internal_lb.zones
  frontend_port              = var.internal_lb.frontend_port
  backend_port               = var.internal_lb.backend_port
  probe_protocol             = var.internal_lb.probe_protocol
  probe_path                 = var.internal_lb.probe_path
  log_analytics_workspace_id = module.monitoring.id
  tags                       = local.tags
}

# VMSS (for_each over nested map)
module "vmss" {
  for_each             = var.vms
  source               = "../../modules/linux-vmss"
  name                 = "${local.name_prefix}-${each.value.name_suffix}"
  resource_group_name  = module.resource_groups[each.value.rg_key].name
  location             = module.resource_groups[each.value.rg_key].location
  sku                  = each.value.sku
  instances            = each.value.instances
  min_instances        = each.value.min_instances
  max_instances        = each.value.max_instances
  zones                = each.value.zones
  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  subnet_id            = module.subnets[each.value.vnet_key].subnet_ids[each.value.subnet_key]

  application_gateway_backend_address_pool_ids = (
    each.value.target_balancer == "appgw" && var.application_gateway.enabled ?
    [module.application_gateway[0].backend_address_pool_id] : []
  )
  load_balancer_backend_address_pool_ids = (
    each.value.target_balancer == "ilb" ?
    [module.internal_lb.backend_address_pool_id] : []
  )

  custom_data = each.key == "frontend" ? local.frontend_cloud_init : local.backend_cloud_init
  tags        = local.tags
}

# Private DNS
module "private_dns" {
  source              = "../../modules/private-dns"
  resource_group_name = module.resource_groups["hub"].name
  dns_zone_names      = var.private_dns_zones
  virtual_network_ids = {
    hub   = module.virtual_networks["hub"].id
    spoke = module.virtual_networks["spoke"].id
  }
  tags = local.tags
}

# PaaS
module "key_vault" {
  source                        = "../../modules/key-vault"
  name                          = substr(replace("${local.name_prefix}-kv-${random_string.unique.result}", "-", ""), 0, 24)
  resource_group_name           = module.resource_groups["hub"].name
  location                      = module.resource_groups["hub"].location
  sku_name                      = "standard"
  purge_protection_enabled      = false
  public_network_access_enabled = false
  log_analytics_workspace_id    = module.monitoring.id
  tags                          = local.tags
}

module "storage_account" {
  source                        = "../../modules/storage-account"
  name                          = replace(lower("${var.project_name}${var.environment}${random_string.unique.result}sa"), "-", "")
  resource_group_name           = module.resource_groups["data"].name
  location                      = module.resource_groups["data"].location
  replication_type              = "LRS"
  public_network_access_enabled = false
  log_analytics_workspace_id    = module.monitoring.id
  tags                          = local.tags
}

module "sql_database" {
  source                        = "../../modules/sql-database"
  server_name                   = "${local.name_prefix}-sqlsvr-${random_string.unique.result}"
  database_name                 = "${local.name_prefix}-db"
  resource_group_name           = module.resource_groups["data"].name
  location                      = module.resource_groups["data"].location
  admin_username                = var.sql_database.admin_username
  admin_password                = var.sql_database.admin_password
  public_network_access_enabled = false
  sku_name                      = var.sql_database.sku_name
  zone_redundant                = var.sql_database.zone_redundant
  max_size_gb                   = var.sql_database.max_size_gb
  log_analytics_workspace_id    = module.monitoring.id
  tags                          = local.tags
}

module "cosmos_db" {
  count                         = var.cosmos_db.enabled ? 1 : 0
  source                        = "../../modules/cosmos-db"
  name                          = "${local.name_prefix}-cosmos-${random_string.unique.result}"
  resource_group_name           = module.resource_groups["data"].name
  location                      = module.resource_groups["data"].location
  zone_redundant                = var.cosmos_db.zone_redundant
  public_network_access_enabled = false
  log_analytics_workspace_id    = module.monitoring.id
  tags                          = local.tags
}

module "redis" {
  count                         = var.redis.enabled ? 1 : 0
  source                        = "../../modules/redis"
  name                          = "${local.name_prefix}-redis-${random_string.unique.result}"
  resource_group_name           = module.resource_groups["data"].name
  location                      = module.resource_groups["data"].location
  sku_name                      = var.redis.sku_name
  family                        = var.redis.family
  capacity                      = var.redis.capacity
  zones                         = var.redis.zones
  public_network_access_enabled = false
  log_analytics_workspace_id    = module.monitoring.id
  tags                          = local.tags
}

# Private Endpoints (for_each over nested map)
module "private_endpoints" {
  for_each            = var.enable_private_endpoints ? var.private_endpoints : {}
  source              = "../../modules/private-endpoint"
  name                = "${local.name_prefix}-${each.value.name_suffix}"
  resource_group_name = module.resource_groups[each.value.rg_key].name
  location            = module.resource_groups[each.value.rg_key].location
  subnet_id           = module.subnets[each.value.vnet_key].subnet_ids[each.value.subnet_key]

  target_resource_id = (
    each.value.target_type == "key_vault" ? module.key_vault.id :
    each.value.target_type == "storage" ? module.storage_account.id :
    each.value.target_type == "sql" ? module.sql_database.server_id :
    each.value.target_type == "cosmos" ? (var.cosmos_db.enabled ? module.cosmos_db[0].id : null) :
    each.value.target_type == "redis" ? (var.redis.enabled ? module.redis[0].id : null) : null
  )

  subresource_names    = each.value.subresource_names
  private_dns_zone_ids = [module.private_dns.zone_ids[each.value.dns_zone_name]]
  tags                 = local.tags
}

# Backup
module "backup" {
  count                 = var.backup.enabled ? 1 : 0
  source                = "../../modules/backup"
  name                  = "${local.name_prefix}-rsv"
  resource_group_name   = module.resource_groups["hub"].name
  location              = module.resource_groups["hub"].location
  storage_mode_type     = var.backup.storage_mode_type
  retention_daily_count = var.backup.retention_daily_count
  tags                  = local.tags
}
