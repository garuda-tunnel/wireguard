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
| `self`                 | yes      | WireGuard local-peer object (e.g. `module.wireguard_tunnel[k].peers["edge"]`): `kernel_ifname`, `private_key`, `address`, optional `listen_port`. Extra attributes are dropped. Sensitive. |
| `remote`               | yes      | WireGuard remote-peer object (e.g. `...peers["core"]`): `public_key`, `endpoint_host`, `listen_port`, optional `preshared_key`. `private_key` is intentionally NOT accepted (least privilege). Sensitive. |
| `allowed_nets`         | no       | List of `AllowedIPs` entries. Default `["0.0.0.0/0","224.0.0.0/4"]` (the `224.0.0.0/4` entry is required for OSPF multicast). |
| `table`                | no       | Default `"off"`. Same semantics as `modules/wireguard/linux`. |
| `persistent_keepalive` | no       | Default `25`. |
| `wireguard_image`      | no       | Image reference for the `wg` container. Empty → chart's pinned digest. |
| `annotations`          | no       | Pod-template annotations passed as `podAnnotations` (e.g. Multus network annotation injected by MAP). |
| `labels`               | no       | Pod-template labels passed as `podLabels` (e.g. garuda profile label injected by MAP). |
| `configmaps`           | no       | Extra ConfigMaps to create before pod admission (e.g. FRR snippets for MAP-injected sidecar). |
| `mtu_policy`           | no       | MTU/MSS policy object. Default `{ site_mtu = 1330 }`. See below. |

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
  namespace = module.garuda_k8s_pt.namespace
  name      = "wg-pt"
  self      = module.wireguard_tunnel_pt.peers["edge"]
  remote    = module.wireguard_tunnel_pt.peers["core"]
  # allowed_nets and mtu_policy default; override per site if needed.
  # annotations and labels are injected by the garuda_guest module:
  annotations = module.garuda_guest_pt.annotations
  labels      = module.garuda_guest_pt.labels
  configmaps  = module.garuda_guest_pt.configmaps
}
```

## What this module does NOT do

- No `hostNetwork`. The pod uses the pod network namespace and attaches
  secondary interfaces declared by `garuda_guest.networks` (e.g.
  `backbone`/`border`).
- No FRR sidecar rendering. The frr-sidecar is injected by Garuda's MAP
  (Kyverno MutatingPolicy) at admission time.
- No hardcoded Multus annotation. The `k8s.v1.cni.cncf.io/networks`
  annotation is passed in via `var.annotations` (from `garuda_guest`).
- No cluster-side CNI install. See `modules/garuda_k8s` for Multus and
  Whereabouts installation.
- No multi-replica scaling. WireGuard private state is single-instance by
  construction.

## Upgrading from 1.x to 2.0.0 (breaking)

- `config` → `self` (`kernel_ifname`, `private_key`, `address`, optional
  `listen_port`; `subnet`/`endpoint_host` removed — they were dead).
- `peer` → `remote` (`public_key`, `endpoint_host`, `listen_port`, optional
  `preshared_key`; `address` removed; `endpoint_listen_port` renamed to
  `listen_port`; `private_key` is not accepted).
- `ospf`, `transit`, `frr_image`, `nic_attach` inputs removed — the frr-sidecar
  and Multus attach are MAP-injected; border-NAT is gated on the presence of the
  `border` interface inside the pod, not an env var.
- `allowed_nets` and `mtu_policy` now have defaults; drop the explicit literals
  if they matched `["0.0.0.0/0","224.0.0.0/4"]` / `{ site_mtu = 1330 }`.
- Pin `?ref=v2.0.0` and `chart_version = "2.0.0"`.
