locals {
  ospf_values = var.ospf == null ? null : {
    router_id          = var.ospf.router_id
    interfaces         = var.ospf.interfaces
    passive_interfaces = var.ospf.passive_interfaces
    default_originate  = var.ospf.default_originate
    redistribute       = var.ospf.redistribute
    transit_provider   = try(var.ospf.transit_provider, false)
  }
}

resource "helm_release" "wireguard" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = false
  chart            = "${path.module}/charts/wireguard"

  # Resolve the frr-sidecar library chart from OCI
  # (oci://ghcr.io/garuda-tunnel/charts, pinned in Chart.yaml) on every apply.
  # Helm fetches it into charts/frr-sidecar-<version>.tgz (gitignored).
  dependency_update = true

  values = [
    yamlencode({
      namespace            = var.namespace
      name                 = var.name
      config               = var.config
      peer                 = var.peer
      allowed_nets         = var.allowed_nets
      table                = var.table
      persistent_keepalive = var.persistent_keepalive
      nic_attach           = var.nic_attach
      images = {
        wireguard = var.wireguard_image
        frr       = var.frr_image
      }
      ospf = local.ospf_values
      transit = {
        interfaces = var.transit.interfaces
      }
    })
  ]
}
