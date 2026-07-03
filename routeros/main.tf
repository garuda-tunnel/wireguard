# modules/wireguard/routeros/main.tf
#
# RouterOS WireGuard endpoint deployment.
# Creates the WireGuard interface, IP address, peer, firewall rules,
# MSS clamping, and interface-list membership on a RouterOS device.
#
# RouterOS uses clamp-to-pmtu bidirectionally; fixed_mss and mss_clamp_enabled
# from mtu_policy are accepted but not applied here (PMTU covers both directions).

locals {
  # RouterOS accepts the uniform mtu_policy contract but applies only effective_mtu
  # to the WireGuard interface MTU. fixed_mss and mss_clamp_enabled are not used:
  # RouterOS clamps MSS via bidirectional clamp-to-pmtu mangle rules instead.
  effective_mtu = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu : var.mtu_policy.effective_mtu
}

resource "routeros_interface_wireguard" "this" {
  name        = var.self.tunnel_name
  listen_port = var.self.listen_port
  private_key = var.self.private_key
  mtu         = local.effective_mtu
  comment     = var.self.tunnel_name
}

resource "routeros_ip_address" "this" {
  address   = "${split("/", var.self.address)[0]}/${split("/", var.subnet)[1]}"
  interface = routeros_interface_wireguard.this.name
  comment   = var.self.tunnel_name
}

resource "routeros_interface_wireguard_peer" "this" {
  interface            = routeros_interface_wireguard.this.name
  public_key           = var.remote.public_key
  allowed_address      = concat(["${split("/", var.remote.address)[0]}/32"], var.allowed_nets)
  endpoint_address     = var.remote.endpoint_host
  endpoint_port        = var.remote.listen_port
  preshared_key        = var.self.preshared_key
  persistent_keepalive = "25s"
  comment              = "${var.self.tunnel_name}:${var.hostname}"
}

resource "routeros_ip_firewall_filter" "wireguard_input" {
  action   = "accept"
  chain    = "input"
  protocol = "udp"
  dst_port = tostring(var.self.listen_port)
  comment  = "${var.self.tunnel_name}-input"
}

resource "routeros_ip_firewall_mangle" "this" {
  chain         = "forward"
  action        = "change-mss"
  new_mss       = "clamp-to-pmtu"
  passthrough   = true
  tcp_flags     = "syn"
  protocol      = "tcp"
  out_interface = routeros_interface_wireguard.this.name
  comment       = "garuda-${var.self.tunnel_name}"
}

resource "routeros_ip_firewall_mangle" "this_return" {
  chain        = "forward"
  action       = "change-mss"
  new_mss      = "clamp-to-pmtu"
  passthrough  = true
  tcp_flags    = "syn"
  protocol     = "tcp"
  in_interface = routeros_interface_wireguard.this.name
  comment      = "garuda-${var.self.tunnel_name}-return"
}

resource "routeros_interface_list_member" "wireguard_lan" {
  interface = routeros_interface_wireguard.this.name
  list      = var.interface_list
  comment   = var.self.tunnel_name
}
