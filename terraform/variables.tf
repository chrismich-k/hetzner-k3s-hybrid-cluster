variable "project_name" {
  type = string
}

variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "Hetzner Cloud API Token"
}

variable "hrobot_api_user" {
  type      = string
  sensitive = true
}

variable "hrobot_api_pass" {
  type      = string
  sensitive = true
}

variable "ssh_key_name" {
  type        = string
  description = "name of the ssh key to use for new hcloud servers at Hetzner"
}

variable "default_ssh_key_path" {
  type        = string
  description = "local path to the default ssh key to use for login to a server"
}

variable "hcloud_node_image" {
  type        = string
  description = "default distribution to use for new hcloud nodes"
  default     = "ubuntu-26.04"
}

variable "cluster_nodes" {
  type = map(object({
    role         = string # "master" or "agent"
    type         = string # "hcloud" or "hrobot"
    mode         = string # "existing" or "new"
    provider_id  = optional(number)
    ipv4         = optional(string) # required for existing hrobot
    ipv6         = optional(string) # required for existing hrobot
    ipv4_priv    = string           # pinned private IP, required for every node
    ssh_port     = optional(number, 22)
    ssh_user     = optional(string, "root")
    ssh_key_path = optional(string)
    server_type  = optional(string) # required for mode="new", eg "cx23"
    location     = optional(string) # optional for mode="new", eg "nbg1"

    # whether Traefik should schedule/listen on this node;
    # enable for public ipv4 nodes and set up your domains for these ipv4
    ingress_target = optional(bool, false)

    # only meaningful for mode="create" hcloud agents: create public IPv4
    # (instead of IPv6-only + the ipv4_gateway workaround).
    # Ignored for masters which will always be IPv4 + IPv6 and for existing
    # hcloud or hrobot nodes (Terraform doesn't manage their networking).
    agent_public_ipv4 = optional(bool, false)

    # arbitrary extra k8s node-labels (key=value)
    node_labels = optional(map(string), {})
  }))

  validation {
    # Terraform can't create dedicated servers, and hrobot masters aren't
    # handled anywhere in locals.tf - both combinations would otherwise just
    # silently vanish from every output with no error at all.
    condition = alltrue([
      for k, v in var.cluster_nodes : !(v.type == "hrobot" && (v.mode != "existing" || v.role != "agent"))
    ])
    error_message = "hrobot cluster_nodes entries must have mode = \"existing\" and role = \"agent\" (Terraform cannot create dedicated servers, and hrobot masters aren't supported)."
  }

  validation {
    condition = alltrue([
      for k, v in var.cluster_nodes : v.mode != "existing" || v.provider_id != null
    ])
    error_message = "every cluster_nodes entry with mode = \"existing\" must set provider_id."
  }

  validation {
    condition = alltrue([
      for k, v in var.cluster_nodes : v.mode != "create" || (v.server_type != null && v.server_type != "")
    ])
    error_message = "every cluster_nodes entry with mode = \"create\" must set server_type."
  }

  validation {
    condition = alltrue([
      for k, v in var.cluster_nodes : v.type != "hrobot" || v.ipv4 != null || v.ipv6 != null
    ])
    error_message = "every hrobot cluster_nodes entry must set ipv4 and/or ipv6 (Ansible needs at least one to reach it over SSH)."
  }

  validation {
    # catches e.g. a stale/copy-pasted ipv4_priv colliding with another node
    # in the same private network
    condition     = length(distinct([for k, v in var.cluster_nodes : v.ipv4_priv])) == length(var.cluster_nodes)
    error_message = "cluster_nodes entries must have unique ipv4_priv values."
  }
}

variable "k3s_gateway_server_name" {
  type = string
}

# Multi-master (embedded-etcd) HA: a Hetzner Cloud "Alias IP" - a second,
# movable private IP on the cloud subnet - that always resolves to whichever
# master currently holds it. This is the stable address k3s masters/agents
# join through, instead of hardcoding one master's own ipv4_priv. Manually
# chosen, NOT auto-derived/allocated - matches every other IP in
# cluster_nodes (no IPAM anywhere in this repo). Pick any free address
# inside ip_range_sub_hcloud that isn't already used as a cluster_nodes
# ipv4_priv - Terraform can't validate CIDR membership here (no clean
# native cidrcontains-equivalent), so double check that yourself.
variable "k3s_master_alias_ipv4_priv" {
  type        = string
  description = "pinned private IP (Hetzner Cloud Alias IP) used as the stable k3s API join address for all masters/agents; must not collide with any cluster_nodes ipv4_priv, and must fall inside ip_range_sub_hcloud"

  validation {
    condition     = !contains([for k, v in var.cluster_nodes : v.ipv4_priv], var.k3s_master_alias_ipv4_priv)
    error_message = "k3s_master_alias_ipv4_priv must not collide with any cluster_nodes ipv4_priv value."
  }
}

# cluster_nodes key of the master that currently holds
# k3s_master_alias_ipv4_priv - this is also the bootstrap master that starts
# the embedded-etcd cluster (`cluster-init: true` in roles/install_k3s_master);
# every other master joins through it instead. There is no automatic
# failover: moving the alias to a different (already-running) master after
# a failure is a manual step - change this value and `terraform apply`
variable "k3s_primary_master" {
  type        = string
  description = "cluster_nodes key of the master that currently holds k3s_master_alias_ipv4_priv and bootstraps the embedded-etcd cluster"

  validation {
    condition     = contains([for k, v in var.cluster_nodes : k if v.role == "master"], var.k3s_primary_master)
    error_message = "k3s_primary_master must name an existing cluster_nodes entry with role = \"master\"."
  }
}

variable "vswitch_id" {
  type        = number
  description = "the id of the existing Hetzner vSwitch the dedicated servers use"
}

variable "vswitch_vlan_id" {
  type        = number
  description = "the vLAN id of vSwitch the dedicated servers use"
}

variable "hetzner_network_name" {
  type        = string
  description = "the name of the private network that will be created in the Hetzner Cloud"
}

variable "ip_range_net_private" {
  default = "10.0.0.0/16"
}

variable "ip_range_sub_vswitch" {
  default = "10.0.2.0/24"
}

variable "ip_range_sub_hcloud" {
  default = "10.0.1.0/24"
}

variable "hcloud_location" {
  type    = string
  default = "fsn1"
}

variable "hcloud_network_zone" {
  type    = string
  default = "eu-central"
}

variable "hcloud_server_image" {
  type    = string
  default = "ubuntu-26.04"
}
