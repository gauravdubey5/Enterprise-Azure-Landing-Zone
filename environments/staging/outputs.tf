# Staging Environment - outputs.tf

output "hub_resource_group_name" {
  value = module.resource_groups["hub"].name
}

output "spoke_resource_group_name" {
  value = module.resource_groups["spoke"].name
}

output "hub_virtual_network_name" {
  value = module.virtual_networks["hub"].name
}

output "spoke_virtual_network_name" {
  value = module.virtual_networks["spoke"].name
}

output "firewall_private_ip" {
  value = var.firewall.enabled ? module.firewall[0].private_ip : null
}

output "application_gateway_public_ip" {
  value = var.application_gateway.enabled ? module.application_gateway[0].public_ip : null
}

output "internal_load_balancer_private_ip" {
  value = module.internal_lb.private_ip
}

output "log_analytics_workspace_id" {
  value = module.monitoring.workspace_id
}

output "vmss_ids" {
  value = { for k, v in module.vmss : k => v.id }
}

output "private_endpoint_ips" {
  value = { for k, v in module.private_endpoints : k => v.private_ip_address }
}
