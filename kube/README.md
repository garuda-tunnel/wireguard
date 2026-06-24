# wireguard/kube

Deploys one WireGuard endpoint as a single-replica Kubernetes Deployment.
The pod is a **vanilla guest**: it accepts `annotations`, `labels`, and
`configmaps` map inputs and has zero garuda knowledge. Garuda's MAP
(Kyverno MutatingPolicy) injects the frr-sidecar, Multus network
annotations, and sysctls at admission time.

## Inputs

| Variable               | Required | Description |
|------------------------|----------|-------------|
| `namespace`            | yes      | Existing namespace, typically `module.garuda_k8s.namespace`. |
| `name`                 | yes      | Deployment name (DNS-1123), e.g. `wg-pt`. |
| `config`               | yes      | WireGuard local-peer config object: `kernel_ifname`, `private_key`, `address`, `subnet`, optional `listen_port`, optional `endpoint_host`. Sensitive. |
| `peer`                 | yes      | WireGuard remote-peer config object: `public_key`, `endpoint_host`, optional `preshared_key`, `address`. Sensitive. |
| `allowed_nets`         | yes      | List of `AllowedIPs` entries. |
| `table`                | no       | Default `"off"`. Same semantics as `modules/wireguard/linux`. |
| `persistent_keepalive` | no       | Default `25`. |
| `ospf`                 | no       | Accepted for backward compat; now inert in the chart (frr-sidecar is MAP-injected). |
| `nic_attach`           | no       | Default `["backbone", "border"]`. Passed to `WG_NIC_ATTACH` env var in the pod. |
| `wireguard_image`      | no       | Image reference for the `wg` container. Empty → chart's pinned digest. |
| `annotations`          | no       | Pod-template annotations passed as `podAnnotations` to the chart (e.g. Multus network annotation injected by MAP). |
| `labels`               | no       | Pod-template labels passed as `podLabels` to the chart (e.g. garuda profile label injected by MAP). |
| `configmaps`           | no       | Extra ConfigMaps to create before pod admission (e.g. FRR snippets for MAP-injected sidecar). |
| `mtu_policy`           | yes      | MTU/MSS policy object. See below. |

### `mtu_policy` object

| Field              | Required | Description |
|--------------------|----------|-------------|
| `site_mtu`         | XOR      | Site MTU; derives `effective_mtu = site_mtu` and `fixed_mss = site_mtu - 40`. |
| `effective_mtu`    | XOR      | Explicit effective MTU (use with `fixed_mss`). |
| `fixed_mss`        | XOR      | Explicit fixed MSS clamp (use with `effective_mtu`). |
| `mss_clamp_enabled`| no       | Default `true`. Gates the inbound fixed-MSS nft rule in `postup.sh`. |

## Outputs

| Output            | Description |
|-------------------|-------------|
| `deployment_name` | Equals `var.name`. |

## Example

```hcl
module "wireguard_kube_pt" {
  source = "../../../modules/wireguard/kube"
  providers = {
    helm       = helm.pt
    kubernetes = kubernetes.pt
  }
  namespace    = module.garuda_k8s_pt.namespace
  name         = "wg-pt"
  config       = local.wg_pt.config
  peer         = local.wg_pt.peer
  allowed_nets = local.wg_pt.allowed_nets
  mtu_policy   = { site_mtu = 1330 }
  # annotations and labels are injected by the garuda_guest module:
  annotations  = module.garuda_guest_pt.annotations
  labels       = module.garuda_guest_pt.labels
  configmaps   = module.garuda_guest_pt.configmaps
}
```

## What this module does NOT do

- No `hostNetwork`. The pod uses the pod network namespace and attaches
  `backbone`/`border` as Multus secondary interfaces.
- No FRR sidecar rendering. The frr-sidecar is injected by Garuda's MAP
  (Kyverno MutatingPolicy) at admission time.
- No hardcoded Multus annotation. The `k8s.v1.cni.cncf.io/networks`
  annotation is passed in via `var.annotations` (from `garuda_guest`).
- No cluster-side CNI install. See `modules/garuda_k8s` for Multus and
  Whereabouts installation.
- No multi-replica scaling. WireGuard private state is single-instance by
  construction.
