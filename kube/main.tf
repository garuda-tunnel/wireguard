locals {
  effective_mtu = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu : var.mtu_policy.effective_mtu
  fixed_mss     = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu - 40 : var.mtu_policy.fixed_mss
  # mss_clamp_enabled is resolved here from the policy object (default true via
  # optional(bool, true) in the type). Task 2 wires it to WG_MSS_CLAMP_ENABLED
  # in the chart env to gate postup.sh's inbound fixed-MSS nft rule.
  mss_clamp_enabled = var.mtu_policy.mss_clamp_enabled

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
  )
  mtu_policy_values = {
    effectiveMtu    = local.effective_mtu
    fixedMss        = local.fixed_mss
    mssClampEnabled = local.mss_clamp_enabled
  }
}

resource "kubernetes_config_map" "garuda_extra" {
  for_each = var.configmaps
  metadata {
    name      = each.key
    namespace = var.namespace
  }
  # each.value is already a { filename => content } map (Decision #11).
  data = each.value
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
      mtuPolicy            = local.mtu_policy_values
      podLabels            = var.labels
      podAnnotations       = var.annotations
      transit = {
        interfaces = var.transit.interfaces
      }
    })
  ]

  depends_on = [kubernetes_config_map.garuda_extra]
}
