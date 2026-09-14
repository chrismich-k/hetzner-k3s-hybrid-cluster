# =================================================
# create private Hetzner network and subnets, route
# =================================================

# create new private network; hetzner console equivalent:
# https://console.hetzner.com/projects/<project_id>/networks
resource "hcloud_network" "k3s_net" {
  name                     = var.hetzner_network_name
  ip_range                 = var.ip_range_net_private
  expose_routes_to_vswitch = true
}

# create subnets; in hetzner console:
# https://console.hetzner.com/projects/<project_id>/networks/<network_id>/subnets

# subnet for hcloud instances
resource "hcloud_network_subnet" "cloud_subnet" {
  network_id   = hcloud_network.k3s_net.id
  type         = "cloud"
  network_zone = var.hcloud_network_zone
  ip_range     = var.ip_range_sub_hcloud
}

# vSwitch subnet for dedicated servers
resource "hcloud_network_subnet" "vswitch_subnet" {
  network_id   = hcloud_network.k3s_net.id
  type         = "vswitch"
  network_zone = var.hcloud_network_zone
  ip_range     = var.ip_range_sub_vswitch
  vswitch_id   = var.vswitch_id
}

# set the route for the network
# var.k3s_gateway_server_name routes ipv4 for nodes without public ipv4
# change in terraform.tfvars and apply to change; see hetzner console:
# https://console.hetzner.com/projects/<project_id>/networks/<network_id>/routes
resource "hcloud_network_route" "to_cloud_master_gateway" {
  network_id  = hcloud_network.k3s_net.id
  destination = "0.0.0.0/0"
  gateway     = merge(local.all_master_servers, local.all_agent_servers)[var.k3s_gateway_server_name].ipv4_priv
}
