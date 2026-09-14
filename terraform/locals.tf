# ===================================================
# group and format server facts to be read by Ansible
# ===================================================

locals {
  ## agents running on hetzner robot server (dedicated or auction)
  existing_hrobot_agents = {
    for k, v in var.cluster_nodes : k => v if v.type == "hrobot" && v.mode == "existing"
  }

  ## group master nodes
  master_nodes = {
    for k, v in var.cluster_nodes : k => v if v.role == "master"
  }

  master_facts = merge(
    {
      for k, s in data.hcloud_server.existing_hcloud_masters : k => {
        provider_id = s.id
        ipv4        = s.ipv4_address
        ipv6        = s.ipv6_address
        ipv4_priv   = hcloud_server_network.existing_cloud_master_node_network[k].ip #var.cluster_nodes[k].ipv4_priv
      }
    },
    {
      for k, s in hcloud_server.new_hcloud_masters : k => {
        provider_id = s.id
        ipv4        = s.ipv4_address
        ipv6        = s.ipv6_address
        ipv4_priv   = hcloud_server_network.new_cloud_master_node_network[k].ip #var.cluster_nodes[k].ipv4_priv
      }
    },
  )

  # will be read by Ansible
  all_master_servers = {
    for k, f in local.master_facts : k => {
      name           = k
      type           = var.cluster_nodes[k].type
      mode           = var.cluster_nodes[k].mode
      wan_ip         = f.ipv4
      ipv4           = f.ipv4
      ipv6           = f.ipv6
      ipv4_priv      = f.ipv4_priv
      ssh_port       = var.cluster_nodes[k].ssh_port
      ssh_user       = var.cluster_nodes[k].ssh_user
      ssh_key_path   = coalesce(var.cluster_nodes[k].ssh_key_path, var.default_ssh_key_path)
      provider_id    = tostring(f.provider_id)
      ingress_target = var.cluster_nodes[k].ingress_target
      node_labels    = var.cluster_nodes[k].node_labels
    }
  }

  ## group agent nodes
  agent_nodes = {
    for k, v in var.cluster_nodes : k => v if v.role == "agent"
  }

  agent_facts = merge(
    {
      for k, s in data.hcloud_server.existing_hcloud_agents : k => {
        provider_id = s.id
        ipv4        = s.ipv4_address
        ipv6        = s.ipv6_address
        ipv4_priv   = hcloud_server_network.existing_cloud_agent_node_network[k].ip
      }
    },
    {
      for k, s in hcloud_server.new_hcloud_agents : k => {
        provider_id = s.id
        ipv4        = s.ipv4_address
        ipv6        = s.ipv6_address
        ipv4_priv   = hcloud_server_network.new_cloud_agent_node_network[k].ip
      }
    },
    {
      for k, s in var.cluster_nodes : k => {
        provider_id = s.provider_id
        ipv4        = s.ipv4
        ipv6        = s.ipv6
        ipv4_priv   = s.ipv4_priv
      } if s.role == "agent" && s.type == "hrobot"
    },
  )

  # will be read by Ansible
  all_agent_servers = {
    for k, f in local.agent_facts : k => {
      name           = k
      type           = var.cluster_nodes[k].type
      mode           = var.cluster_nodes[k].mode
      wan_ip         = try(coalesce(f.ipv4, f.ipv6), null)
      ipv4           = f.ipv4
      ipv6           = f.ipv6
      ipv4_priv      = f.ipv4_priv
      ssh_port       = var.cluster_nodes[k].ssh_port
      ssh_user       = var.cluster_nodes[k].ssh_user
      ssh_key_path   = coalesce(var.cluster_nodes[k].ssh_key_path, var.default_ssh_key_path)
      provider_id    = tostring(f.provider_id)
      ingress_target = var.cluster_nodes[k].ingress_target
      node_labels    = var.cluster_nodes[k].node_labels
    }
  }

  hcloud_network_mask = split("/", hcloud_network.k3s_net.ip_range)[1]
}
