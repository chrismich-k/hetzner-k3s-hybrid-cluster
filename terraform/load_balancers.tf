# =================================================
# optional Hetzner Cloud Load Balancers, one per var.load_balancers entry
# =================================================

# Only the LB itself and its private-network attachment are managed here.
# Services (80/443 -> NodePorts) and targets are deliberately NOT: the
# Hetzner Cloud Controller Manager (roles/hetzner_k3s_hccm) adopts this LB
# by name via the "load-balancer.hetzner.cloud/name" annotation on a k8s
# Service of type LoadBalancer (roles/traefik_loadbalancer) and manages
# both from that Service's spec - defining them here as well would make
# Terraform and HCCM overwrite each other on every apply/reconcile.
# Creating the LB here rather than letting HCCM create it gives it a
# stable public IP (known before DNS is set up) and a lifecycle independent
# of the k8s Service.
resource "hcloud_load_balancer" "lb" {
  for_each           = var.load_balancers
  name               = "${var.project_name}-${each.key}"
  load_balancer_type = each.value.type
  location           = each.value.location
  # HCCM deletes the LB of a LoadBalancer Service when that Service goes
  # away - unless it's delete-protected (it then just logs and skips it,
  # confirmed in HCCM's EnsureLoadBalancerDeleted). Keeps the LB and its IP
  # owned by Terraform alone. To remove a LB, first set its
  # delete_protection = false and apply (the Hetzner API refuses to delete
  # a protected LB), then remove the entry.
  delete_protection = each.value.delete_protection

  lifecycle {
    # HCCM tags the LBs it manages with its own labels (e.g.
    # hcloud-ccm/service-uid) and attaches targets itself - don't let
    # Terraform strip either again on the next apply
    ignore_changes = [labels, target]
  }
}

# Pinned to the hcloud subnet explicitly: private LB targets can only be
# cloud servers anyway (the vSwitch subnet's dedicated servers could only
# be added as public-IP targets), and HCCM reaches its targets over this
# private network ("load-balancer.hetzner.cloud/use-private-ip").
resource "hcloud_load_balancer_network" "lb" {
  for_each         = var.load_balancers
  load_balancer_id = hcloud_load_balancer.lb[each.key].id
  subnet_id        = hcloud_network_subnet.cloud_subnet.id
}
