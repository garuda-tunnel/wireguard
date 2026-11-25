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
  # var.remote's type, so it can never reach these values or state. The secret
  # leaves (private_key, preshared_key, peer public_key) are NOT here: they
  # travel in kubernetes_secret_v1.credentials, because the helm provider
  # prints the deployed values (metadata.values) unredacted in plans.
  wg_config = {
    kernel_ifname = var.self.kernel_ifname
    address       = var.self.address
    listen_port   = var.self.listen_port
  }
  wg_peer = {
    endpoint_host = var.remote.endpoint_host
    listen_port   = var.remote.listen_port
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

# Tunnel keys, Terraform-owned. A null preshared key is written as "": the
# image entrypoint treats an empty WG_PEER_PRESHARED_KEY as absent, and a
# fixed key set avoids map keys whose presence is unknown at plan. The
# Deployment's secret.reloader.stakater.com/reload annotation names this
# Secret, so Stakater Reloader rolls the pod when the keys change.
resource "kubernetes_secret_v1" "credentials" {
  metadata {
    name      = "wg-${var.name}-credentials"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    WG_PRIVATE_KEY        = var.self.private_key
    WG_PEER_PUBLIC_KEY    = var.remote.public_key
    WG_PEER_PRESHARED_KEY = var.remote.preshared_key != null ? var.remote.preshared_key : ""
  }
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
      namespace = var.namespace
      name      = var.name
      # This reference (not a literal) orders the credentials Secret before the Helm upgrade.
      credentialsSecretName = kubernetes_secret_v1.credentials.metadata[0].name
      config                = local.wg_config
      peer                  = local.wg_peer
      allowed_nets          = var.allowed_nets
      table                 = var.table
      persistent_keepalive  = var.persistent_keepalive
      images                = local.images_override
      mtuPolicy             = local.mtu_policy_values
      podLabels             = var.labels
      podAnnotations        = var.annotations
    })
  ]

  depends_on = [kubernetes_config_map.garuda_extra]
}
