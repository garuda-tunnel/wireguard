# wireguard/routeros

Deploys a WireGuard endpoint onto a RouterOS device. Creates the WireGuard
interface, IP address, peer, firewall rules, MSS clamping, OSPF instance,
and endpoint-sync bypass on the device.

## Interface naming

RouterOS resource names are taken from `self.tunnel_name` (env-prefixed,
e.g. `prod-hub-edge`). This ensures all resources on a shared RouterOS device
remain unique across environments.

Use `wireguard/tunnel` as the source for `self` and `remote` — it emits both
`tunnel_name` (env-prefixed, used here) and `kernel_ifname` (raw, used by
`wireguard/linux`). Pass the `peers["..."]` objects through unchanged; `remote`
deliberately excludes `private_key` (least privilege).

## Inputs

| Name | Required | Description |
|---|---|---|
| `hostname` | yes | RouterOS inventory hostname (used in resource comments). |
| `self` | yes | Canonical tunnel config for the local endpoint (from `wireguard/tunnel` output). Full peer object. |
| `remote` | yes | Canonical tunnel config for the remote endpoint. Must include `endpoint_host`; `private_key` is intentionally excluded. |
| `subnet` | yes | CIDR subnet for the WireGuard tunnel. |
| `allowed_nets` | yes | Additional AllowedIPs routed through the tunnel. |
| `interface_list` | no | RouterOS interface list to join (default: `LAN`). |
| `ospf_router_id` | yes | OSPF router ID for this tunnel instance. |
| `ospf_area` | no | OSPF area (default: `0.0.0.0`). |

## Outputs

| Name | Description |
|---|---|
| `bypass_table_name` | Name of the per-tunnel bypass routing table. Caller must install a default route into this table. |
