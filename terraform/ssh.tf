# use existing key at Hetzner
data "hcloud_ssh_key" "main_ssh_key" {
  name = var.ssh_key_name
}
