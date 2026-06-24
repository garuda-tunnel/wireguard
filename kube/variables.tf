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

variable "config" {
  description = "WireGuard local-peer configuration (matches modules/wireguard/linux config shape)."
  type = object({
    kernel_ifname = string
    private_key   = string
    address       = string
    subnet        = string
    listen_port   = optional(number)
    endpoint_host = optional(string)
  })
  sensitive = true

  validation {
    condition     = length(var.config.kernel_ifname) <= 15
    error_message = "config.kernel_ifname must be at most 15 characters (Linux IFNAMSIZ-1)."
  }
}

variable "peer" {
  description = <<EOT
WireGuard remote-peer configuration. `endpoint_host` is the bare
hostname or IP (without port); the chart joins it with
`endpoint_listen_port` to produce the `host:port` form the image
entrypoint expects.
EOT
  type = object({
    public_key           = string
    endpoint_host        = string
    endpoint_listen_port = number
    preshared_key        = optional(string)
    address              = string
  })
  sensitive = true
}

variable "allowed_nets" {
  description = "AllowedIPs entries for the peer (semantics identical to modules/wireguard/linux)."
  type        = list(string)
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

variable "ospf" {
  description = <<EOT
Structured OSPF intent (accepted for backward compat; now inert in the
chart — frr-sidecar is MAP-injected by Kyverno). The ospf field is still
accepted by the values schema and may be used by the MAP profile lookup.
EOT
  type = object({
    router_id          = string
    interfaces         = list(string)
    passive_interfaces = optional(list(string), [])
    default_originate  = optional(bool, false)
    redistribute       = optional(list(string), [])
    transit_provider   = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.ospf == null || can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.ospf.router_id))
    error_message = "ospf.router_id must be an IPv4-formatted string."
  }

  validation {
    condition     = var.ospf == null || length(var.ospf.interfaces) > 0
    error_message = "ospf.interfaces must be non-empty when ospf is set."
  }

  validation {
    condition = (
      var.ospf == null
      || alltrue([for r in var.ospf.redistribute : contains(["connected", "kernel", "static"], r)])
    )
    error_message = "ospf.redistribute values must be subset of ['connected', 'kernel', 'static']."
  }
}

variable "transit" {
  # DEPRECATED: kept inert per Phase 4+5 Decision #5; transit-watcher is now
  # MAP-injected (Kyverno MutatingPolicy), not chart-rendered. This variable
  # is accepted for backward compat and removed in follow-up cleanup.
  description = "Inert — accepted for backward compat only. Transit-watcher is now MAP-injected."
  type = object({
    interfaces = list(string)
  })
  default = {
    interfaces = []
  }
}

variable "nic_attach" {
  description = "Secondary networks the pod attaches to via Multus. Becomes the k8s.v1.cni.cncf.io/networks annotation."
  type        = list(string)
  default     = ["backbone", "border"]
}

variable "wireguard_image" {
  description = "Image reference for the wg container. Empty ⇒ use the chart's pinned digest."
  type        = string
  default     = ""
}

variable "frr_image" {
  # DEPRECATED: kept inert per Phase 4+5 Decision #5; frr-sidecar is now
  # MAP-injected (Kyverno MutatingPolicy), not chart-rendered. This variable
  # is accepted for backward compat and removed in follow-up cleanup.
  description = "Inert — accepted for backward compat only. frr-sidecar is now MAP-injected."
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Pinned OCI chart version (exact semver). Bumped in lockstep with Chart.yaml by release-please."
  type        = string
  default     = "1.1.0" # x-release-please-version

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
