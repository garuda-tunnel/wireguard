locals {
  ospf_values = var.ospf == null ? null : {
    router_id          = var.ospf.router_id
    interfaces         = var.ospf.interfaces
    passive_interfaces = var.ospf.passive_interfaces
    default_originate  = var.ospf.default_originate
    redistribute       = var.ospf.redistribute
    transit_provider   = try(var.ospf.transit_provider, false)
  }
  images_override = merge(
    var.wireguard_image == "" ? {} : { wireguard = var.wireguard_image },
    var.frr_image == "" ? {} : { frr = var.frr_image },
  )
}

resource "helm_release" "wireguard" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = false

  # Consume the published chart from OCI by an exact pinned version.
  # Source stays in kube/charts/wireguard for release-please / CI / local dev.
  repository = "oci://ghcr.io/garuda-tunnel/charts"
  chart      = "wireguard"
  version    = var.chart_version

  # No-op for the OCI path (dependency is vendored in the published tgz);
  # kept so the local-path dev/hotfix escape hatch still resolves frr-sidecar.
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
      images               = local.images_override
      ospf                 = local.ospf_values
      transit = {
        interfaces = var.transit.interfaces
      }
    })
  ]
}
