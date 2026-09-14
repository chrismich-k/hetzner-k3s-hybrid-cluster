# ========================================================
# create new nodes or query existing nodes; attach network
# ========================================================

## master nodes

# create new cloud instance, always public ipv4+ipv6
resource "hcloud_server" "new_hcloud_masters" {
  for_each = {
    for k, v in var.cluster_nodes : k => v if v.role == "master" && v.type == "hcloud" && v.mode == "create"
  }

  name        = each.key
  server_type = each.value.server_type
  location    = each.value.location
  image       = var.hcloud_node_image
  ssh_keys    = [data.hcloud_ssh_key.main_ssh_key.id] # [hcloud_ssh_key.admin.id]

  labels = {
    "role"          = "master"
    "instance.type" = "hcloud"
  }
}

# existing cloud instance
data "hcloud_server" "existing_hcloud_masters" {
  for_each = {
    for k, v in var.cluster_nodes : k => v if v.role == "master" && v.type == "hcloud" && v.mode == "existing"
  }

  id = each.value.provider_id
}

## agent nodes

# create new cloud instance - IPv6-only by default (see the
# ipv4_gateway/ipv4_route_via_gateway Ansible roles for how such nodes reach
# IPv4-only internet destinations), or dual-stack if agent_public_ipv4 = true.
resource "hcloud_server" "new_hcloud_agents" {
  for_each = {
    for k, v in var.cluster_nodes : k => v if v.role == "agent" && v.type == "hcloud" && v.mode == "create"
  }

  name        = each.key
  server_type = each.value.server_type
  location    = each.value.location
  image       = var.hcloud_node_image
  ssh_keys    = [data.hcloud_ssh_key.main_ssh_key.id] # [hcloud_ssh_key.admin.id]

  # omitting the "public_net" block uses the Hetzner defaults (ipv4+ipv6),
  # creating the block overrides defaults for public ipv6 only 
  dynamic "public_net" {
    for_each = each.value.agent_public_ipv4 ? [] : [1]
    content {
      ipv4_enabled = false
      ipv6_enabled = true
    }
  }

  labels = {
    "role"          = "agent"
    "instance.type" = "hcloud"
  }
}

# scenario b: use existing cloud instance
data "hcloud_server" "existing_hcloud_agents" {
  for_each = {
    for k, v in var.cluster_nodes : k => v if v.role == "agent" && v.type == "hcloud" && v.mode == "existing"
  }

  id = each.value.provider_id
}

## attach network to nodes

# new hcloud masters: always join private network
resource "hcloud_server_network" "new_cloud_master_node_network" {
  for_each = hcloud_server.new_hcloud_masters

  server_id  = each.value.id
  network_id = hcloud_network.k3s_net.id
  ip         = var.cluster_nodes[each.key].ipv4_priv

  # only the currently-designated holder gets the alias (also the
  # embedded-etcd bootstrap master, see roles/install_k3s_master) - every
  # other master gets an explicit [] here, not null: alias_ips is
  # optional+computed on this resource, so omitting it would just keep
  # whatever Terraform last stored in state instead of detaching it when
  # k3s_primary_master moves to a different master.
  alias_ips = each.key == var.k3s_primary_master ? [var.k3s_master_alias_ipv4_priv] : []
}

# existing hcloud masters: private net + subnets are always created fresh,
# so an existing server can never already be a member -> always attach
resource "hcloud_server_network" "existing_cloud_master_node_network" {
  for_each = data.hcloud_server.existing_hcloud_masters

  server_id  = each.value.id
  network_id = hcloud_network.k3s_net.id
  ip         = var.cluster_nodes[each.key].ipv4_priv

  # see new_cloud_master_node_network above for why this is [] rather than
  # null/omitted on every non-holder master
  alias_ips = each.key == var.k3s_primary_master ? [var.k3s_master_alias_ipv4_priv] : []
}

# new hcloud agents: always join private network
resource "hcloud_server_network" "new_cloud_agent_node_network" {
  for_each = hcloud_server.new_hcloud_agents

  server_id  = each.value.id
  network_id = hcloud_network.k3s_net.id
  ip         = var.cluster_nodes[each.key].ipv4_priv
}

# existing hcloud agents: private net + subnets are always created fresh,
# so an existing server can never already be a member -> always attach
resource "hcloud_server_network" "existing_cloud_agent_node_network" {
  for_each = data.hcloud_server.existing_hcloud_agents

  server_id  = each.value.id
  network_id = hcloud_network.k3s_net.id
  ip         = var.cluster_nodes[each.key].ipv4_priv
}
