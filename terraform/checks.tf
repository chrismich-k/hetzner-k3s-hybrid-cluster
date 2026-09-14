# Soft assertions about cluster_nodes: report a warning on plan/apply without
# blocking it. Use terraform/variables.tf's `validation` blocks instead for
# anything that should hard-fail.

check "agent_public_ipv4_scope" {
  assert {
    # agent_public_ipv4 only has any effect for role="agent" + type="hcloud" +
    # mode="create" nodes (see cluster_nodes.tf's new_hcloud_agents) - setting
    # it anywhere else is silently ignored
    condition = alltrue([
      for k, v in var.cluster_nodes :
      !v.agent_public_ipv4 || (v.role == "agent" && v.type == "hcloud" && v.mode == "create")
    ])
    error_message = "agent_public_ipv4 = true is set on a node where it has no effect (only role=\"agent\", type=\"hcloud\", mode=\"create\" nodes use it) - check cluster_nodes."
  }
}

check "at_least_one_ingress_target" {
  assert {
    condition     = anytrue([for k, v in var.cluster_nodes : v.ingress_target])
    error_message = "no cluster_nodes entry has ingress_target = true - Traefik's DaemonSet will have no node to schedule onto."
  }
}
