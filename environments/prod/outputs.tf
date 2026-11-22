# Prod Environment - outputs.tf

output "hub_resource_group_name" {
  description = "The name of the Hub Resource Group"
  value       = module.resource_groups["hub"].name
}

output "spoke_resource_group_name" {
  description = "The name of the Spoke Resource Group"
  value       = module.resource_groups["spoke"].name
}

output "hub_virtual_network_name" {
  description = "The name of the Hub Virtual Network"
  value       = module.virtual_networks["hub"].name
}

output "spoke_virtual_network_name" {
  description = "The name of the Spoke Virtual Network"
  value       = module.virtual_networks["spoke"].name
}

output "firewall_private_ip" {
  description = "Private IP of Azure Firewall (egress next-hop)"
  value       = var.firewall.enabled ? module.firewall[0].private_ip : null
}

output "firewall_public_ip" {
  description = "Public IP of Azure Firewall"
  value       = var.firewall.enabled ? module.firewall[0].public_ip : null
}

output "application_gateway_public_ip" {
  description = "Public IP address of Application Gateway WAF (primary ingress)"
  value       = var.application_gateway.enabled ? module.application_gateway[0].public_ip : null
}

output "internal_load_balancer_private_ip" {
  description = "Private IP address of Internal Load Balancer"
  value       = module.internal_lb.private_ip
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace GUID"
  value       = module.monitoring.workspace_id
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of Azure SQL Server"
  value       = module.sql_database.server_fqdn
}

output "key_vault_uri" {
  description = "URI of Azure Key Vault"
  value       = module.key_vault.vault_uri
}

output "storage_account_name" {
  description = "Name of the Azure Storage Account"
  value       = module.storage_account.name
}

output "vmss_ids" {
  description = "Map of VMSS tier names to resource IDs"
  value       = { for k, v in module.vmss : k => v.id }
}

output "private_endpoint_ips" {
  description = "Map of Private Endpoint names to private IP addresses"
  value       = { for k, v in module.private_endpoints : k => v.private_ip_address }
}
