output "master_nodes" {
  value = local.all_master_servers
}

output "agent_nodes" {
  value = local.all_agent_servers
}

# Not a secret - lets Ansible know which node acts as the IPv4 gateway
# (that node knows its own ipv4/ipv4_priv already via master_nodes/agent_nodes,
# so nothing else needs to flow through here).
output "k3s_gateway_server_name" {
  value = var.k3s_gateway_server_name
}

# Not a secret - the stable private IP (Hetzner Cloud Alias IP) masters/agents
# join through instead of one master's own ipv4_priv; see cluster_nodes.tf's
# alias_ips on hcloud_server_network for which master currently holds it.
output "k3s_master_alias_ipv4_priv" {
  value = var.k3s_master_alias_ipv4_priv
}

# Not a secret - lets each master know whether it is the one that currently
# holds k3s_master_alias_ipv4_priv and therefore bootstraps the embedded-etcd
# cluster (cluster-init: true); every other master joins through it instead.
output "k3s_primary_master" {
  value = var.k3s_primary_master
}

# Not a secret - lets Ansible build the vSwitch VLAN sub-interface name
# (<physical-iface>.<vswitch_vlan_id>) on hrobot nodes.
output "vswitch_vlan_id" {
  value = var.vswitch_vlan_id
}

# Not a secret - lets roles/ipv4_gateway source the subnet it routes/NATs for
# directly from ip_range_sub_hcloud instead of duplicating it as a hardcoded
# role default that has to be kept in sync by hand.
output "ip_range_sub_hcloud" {
  value = var.ip_range_sub_hcloud
}

# Not a secret - the first usable address of ip_range_net_private, which is
# the real next-hop Hetzner's own DHCP announces for the whole private CIDR
# to hcloud nodes (confirmed via `ip route show` on any hcloud node). Computed
# here so roles/ipv4_route_via_gateway's hetzner_private_network_gateway_ip
# always tracks ip_range_net_private instead of being hardcoded separately.
output "hetzner_private_network_gateway_ip" {
  value = cidrhost(var.ip_range_net_private, 1)
}

# Not a secret - raw passthrough of the whole private-network CIDR, so
# roles/hrobot_vswitch_vlan's hetzner_private_network_cidr can source it
# directly instead of duplicating the literal.
output "ip_range_net_private" {
  value = var.ip_range_net_private
}

# Not a secret - the prefix length of ip_range_sub_vswitch (e.g. 24 from
# "10.0.2.0/24"), for roles/hrobot_vswitch_vlan's vswitch_subnet_prefix_len.
output "vswitch_subnet_prefix_len" {
  value = tonumber(split("/", var.ip_range_sub_vswitch)[1])
}

# Not a secret - the first usable address of ip_range_sub_vswitch. This is
# Hetzner's own fixed SDN router address on the vSwitch-side subnet, NOT a
# node we manage - unrelated to k3s_gateway_server_name (which names a
# specific node's ipv4_priv for the unrelated 0.0.0.0/0 hcloud NAT route).
# Feeds roles/hrobot_vswitch_vlan's hetzner_vswitch_gateway_ip; see that
# role's defaults/main.yaml for why this differs from
# hetzner_private_network_gateway_ip above.
output "hetzner_vswitch_gateway_ip" {
  value = cidrhost(var.ip_range_sub_vswitch, 1)
}

# Single source of truth for the Hetzner credentials that Ansible also needs
# (e.g. to create the "hcloud" k8s Secret consumed by HCCM/CSI). Marked
# sensitive so plain `terraform output`/plan/apply logs redact them; `-json`
# still includes the real values, which is what 00_setup_inventory.yaml uses.
output "hcloud_token" {
  value     = var.hcloud_token
  sensitive = true
}

output "hrobot_api_user" {
  value     = var.hrobot_api_user
  sensitive = true
}

output "hrobot_api_pass" {
  value     = var.hrobot_api_pass
  sensitive = true
}
