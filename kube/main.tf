locals {
  effective_mtu = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu : var.mtu_policy.effective_mtu
  fixed_mss     = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu - 40 : var.mtu_policy.fixed_mss
  # mss_clamp_enabled is resolved here from the policy object (default true via
  # optional(bool, true) in the type). Wired to WG_MSS_CLAMP_ENABLED in the chart
  # env to gate postup.sh's inbound fixed-MSS nft rule.
  mss_clamp_enabled = var.mtu_policy.mss_clamp_enabled

  # Map the narrowed self/remote peer objects onto the chart's kept config/peer
  # value objects. The chart value keys mirror the tunnel output field names 1:1
  # (peer.listen_port, not endpoint_listen_port). remote.private_key is not in
  # var.remote's type, so it can never reach these values or state.
  wg_config = {
    kernel_ifname = var.self.kernel_ifname
    private_key   = var.self.private_key
    address       = var.self.address
    listen_port   = var.self.listen_port
  }
  wg_peer = {
    public_key    = var.remote.public_key
    endpoint_host = var.remote.endpoint_host
    listen_port   = var.remote.listen_port
    preshared_key = var.remote.preshared_key
  }

  images_override = var.wireguard_image == "" ? {} : { wireguard = var.wireguard_image }

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
  # kept so the local-path dev/hotfix escape hatch resolves any chart deps.
  dependency_update = true

  values = [
    yamlencode({
      namespace            = var.namespace
      name                 = var.name
      config               = local.wg_config
      peer                 = local.wg_peer
      allowed_nets         = var.allowed_nets
      table                = var.table
      persistent_keepalive = var.persistent_keepalive
      images               = local.images_override
      mtuPolicy            = local.mtu_policy_values
      podLabels            = var.labels
      podAnnotations       = var.annotations
    })
  ]

  depends_on = [kubernetes_config_map.garuda_extra]
}
