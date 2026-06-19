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

variable "mtu_policy" {
  description = "Site MTU/MSS policy. site_mtu derives effective_mtu and fixed_mss; otherwise effective_mtu and fixed_mss must be supplied explicitly."
  nullable    = false

  type = object({
    site_mtu          = optional(number)
    effective_mtu     = optional(number)
    fixed_mss         = optional(number)
    mss_clamp_enabled = optional(bool, true)
  })

  validation {
    condition = (
      (var.mtu_policy.site_mtu != null && var.mtu_policy.effective_mtu == null && var.mtu_policy.fixed_mss == null) ||
      (var.mtu_policy.site_mtu == null && var.mtu_policy.effective_mtu != null && var.mtu_policy.fixed_mss != null)
    )
    error_message = "Set either mtu_policy.site_mtu or both mtu_policy.effective_mtu and mtu_policy.fixed_mss."
  }

  validation {
    condition = (
      var.mtu_policy.site_mtu == null ||
      (var.mtu_policy.site_mtu >= 1280 && var.mtu_policy.site_mtu <= 1420)
    )
    error_message = "mtu_policy.site_mtu must be between 1280 and 1420."
  }

  validation {
    condition = (
      var.mtu_policy.effective_mtu == null ||
      (var.mtu_policy.effective_mtu >= 1280 && var.mtu_policy.effective_mtu <= 1420)
    )
    error_message = "mtu_policy.effective_mtu must be between 1280 and 1420."
  }

  validation {
    condition = (
      var.mtu_policy.fixed_mss == null ||
      (var.mtu_policy.fixed_mss >= 536 && var.mtu_policy.fixed_mss <= 1460)
    )
    error_message = "mtu_policy.fixed_mss must be between 536 and 1460."
  }

  validation {
    condition = (
      var.mtu_policy.fixed_mss == null ||
      var.mtu_policy.effective_mtu == null ||
      var.mtu_policy.fixed_mss <= var.mtu_policy.effective_mtu - 40
    )
    error_message = "mtu_policy.fixed_mss must be less than or equal to mtu_policy.effective_mtu - 40."
  }
}
