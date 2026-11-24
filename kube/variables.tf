variable "namespace" {
  description = "Existing Kubernetes namespace, sourced from module.garuda_k8s.namespace."
  type        = string
}

variable "name" {
  description = "Deployment name, for example 'wg-pt'."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid DNS-1123 label."
  }
}

variable "self" {
  description = "Local peer object (e.g. module.wireguard_tunnel[k].peers[\"edge\"]). Extra attributes are dropped."
  sensitive   = true
  type = object({
    kernel_ifname = string
    private_key   = string
    address       = string
    listen_port   = optional(number)
  })

  validation {
    condition     = length(var.self.kernel_ifname) <= 15
    error_message = "self.kernel_ifname must be at most 15 characters (Linux IFNAMSIZ-1)."
  }

  validation {
    condition = (
      var.self.listen_port == null ||
      (var.self.listen_port != 51820 && var.self.listen_port != 51821)
    )
    error_message = "self.listen_port must not be 51820 or 51821: these are the standard WireGuard ports, which k3s flannel wireguard-native uses on every node, and a tunnel hostPort on them would steal flannel's packets. Use any other port."
  }
}

variable "remote" {
  description = "Remote peer object (e.g. module.wireguard_tunnel[k].peers[\"core\"]). private_key is intentionally NOT in the type."
  sensitive   = true
  type = object({
    public_key    = string
    endpoint_host = string
    listen_port   = number
    preshared_key = optional(string)
  })
}

variable "allowed_nets" {
  description = "AllowedIPs entries for the peer (semantics identical to modules/wireguard/linux)."
  type        = list(string)
  default     = ["0.0.0.0/0", "224.0.0.0/4"]
}

variable "table" {
  description = "WireGuard routing table directive. 'off' disables WireGuard-managed routes."
  type        = string
  default     = "off"
}

variable "persistent_keepalive" {
  description = "WireGuard PersistentKeepalive in seconds."
  type        = number
  default     = 25
}

variable "wireguard_image" {
  description = "Image reference for the wg container. Empty ⇒ use the chart's pinned digest."
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Pinned OCI chart version (exact semver). Bumped in lockstep with Chart.yaml by release-please."
  type        = string
  default     = "2.0.2" # x-release-please-version

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.chart_version))
    error_message = "chart_version must be exact semver MAJOR.MINOR.PATCH (no range, no 'latest')."
  }
}

variable "annotations" {
  description = "Pod-template annotations (spec.template.metadata.annotations). From garuda_guest.annotations."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Pod-template labels (spec.template.metadata.labels). From garuda_guest.labels."
  type        = map(string)
  default     = {}
}

variable "configmaps" {
  description = "Extra ConfigMaps to create before pod admission (Tier 2/3 FRR snippets). From garuda_guest.configmaps."
  type        = map(map(string))
  default     = {}
}

variable "mtu_policy" {
  description = "Site MTU/MSS policy. site_mtu derives effective_mtu and fixed_mss; otherwise effective_mtu and fixed_mss must be supplied explicitly."
  nullable    = false
  default     = { site_mtu = 1330 }

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
