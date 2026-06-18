# modules/wireguard/routeros/variables.tf
#
# RouterOS WireGuard endpoint deployment module.
# Accepts canonical tunnel data from modules/wireguard/tunnel and
# RouterOS-specific deployment arguments.

variable "hostname" {
  description = "RouterOS inventory hostname (used in resource comments)."
  type        = string
}

variable "config" {
  description = "Canonical tunnel config object for the RouterOS endpoint (from wireguard/tunnel output)."
  type = object({
    tunnel_name   = string
    kernel_ifname = string
    address       = string
    private_key   = string
    public_key    = string
    preshared_key = string
    listen_port   = number
    endpoint_host = optional(string)
  })
}

variable "peer" {
  description = "Canonical tunnel config object for the remote endpoint (from wireguard/tunnel output)."
  type = object({
    tunnel_name   = string
    kernel_ifname = string
    address       = string
    private_key   = string
    public_key    = string
    preshared_key = string
    listen_port   = number
    endpoint_host = optional(string)
  })

  validation {
    condition     = try(trimspace(var.peer.endpoint_host) != "", false)
    error_message = "RouterOS tunnel peers must define peer.endpoint_host for endpoint bypass."
  }
}

variable "subnet" {
  description = "CIDR subnet of the WireGuard tunnel (e.g. 198.51.100.0/28)."
  type        = string
}

variable "allowed_nets" {
  description = "Additional AllowedIPs routed through the tunnel beyond the peer /32."
  type        = list(string)
}

variable "interface_list" {
  description = "RouterOS interface list to add the WireGuard tunnel interface to."
  type        = string
  default     = "LAN"
}

variable "router_id" {
  description = "Unique RouterOS OSPF router ID for this tunnel-specific instance."
  type        = string
}

variable "ospf_area" {
  description = "OSPF area identifier for this tunnel-specific instance."
  type        = string
  default     = "0.0.0.0"
}

variable "mtu" {
  description = "WireGuard interface MTU on the RouterOS side. Default 1370 aligns with the hub side to remove the 1420/1370 asymmetry (PPPoE-1492 underlay minus WG 60-byte overhead). Min-safe for wg-hub-ros; set 1280 for nested tunnels (e.g. wg-firezone)."
  type        = number
  default     = 1370
}
