# Changelog

## [1.1.0](https://github.com/garuda-tunnel/wireguard-internal/compare/v1.0.0...v1.1.0) (2026-06-19)


### Features

* **chart:** bump frr-sidecar dependency 0.1.0 -&gt; 0.2.0 ([bc5ffb9](https://github.com/garuda-tunnel/wireguard-internal/commit/bc5ffb9e49c48659e0de4bc6ddcdc8c8ed9341ce))
* **chart:** bump frr-sidecar dependency 0.1.0 → 0.2.0 ([cfc1662](https://github.com/garuda-tunnel/wireguard-internal/commit/cfc1662d60c9207feea5d0dca7219cb054c273b7))
* **k3s-edge:** Phase 1 — modules/garuda_k8s + modules/wireguard/kube + operator scripts ([#39](https://github.com/garuda-tunnel/wireguard-internal/issues/39)) ([62406fd](https://github.com/garuda-tunnel/wireguard-internal/commit/62406fd5ac57c16bafe1c64c796b4b5c144b2452))
* normalize wireguard kube mtu policy ([3e77d56](https://github.com/garuda-tunnel/wireguard-internal/commit/3e77d56b25aabf63f31f2f21998f097fc2b5a261))
* pin wireguard image digest in chart (Phase 1) ([04d18f5](https://github.com/garuda-tunnel/wireguard-internal/commit/04d18f5be2f6e475d4df8d54baba29745580ef66))
* pin wireguard image digest in chart; TF conditional override; caller main-trigger + inputs ([3a79769](https://github.com/garuda-tunnel/wireguard-internal/commit/3a79769bc988aebdc662d307f7a466fe0e8d8211))
* unify MTU/MSS policy — mtu_policy contract + chart 1.0.0 ([f2bf6bf](https://github.com/garuda-tunnel/wireguard-internal/commit/f2bf6bf1c454c8f45596810100a9d1dfab265517))
* wireguard tag-model publish (release-gated sync+publish, dev-image, chart .Chart.Version fallback) ([3ad4ebd](https://github.com/garuda-tunnel/wireguard-internal/commit/3ad4ebd82de3364bfba21889cb231ba5d8587279))
* wireguard tag-model publish (sub-project A) ([ed6a518](https://github.com/garuda-tunnel/wireguard-internal/commit/ed6a518be0be4ebe7be30a1fe657f3a70bab1620))
* **wireguard:** align WG tunnel MTU (MTU/MSS Task 6) ([8d39e22](https://github.com/garuda-tunnel/wireguard-internal/commit/8d39e22de7581572f8800d92ce3f76d0a73b9251))
* **wireguard:** align WG tunnel MTU across both sides ([a8702ef](https://github.com/garuda-tunnel/wireguard-internal/commit/a8702ef702fcc0c125f43c412a7496835112357c))
* **wireguard:** consume frr-sidecar via OCI; drop local template checksum ([968db37](https://github.com/garuda-tunnel/wireguard-internal/commit/968db37691d9e98c37276de61c579eae14691a9e))
* **wireguard:** emit app.kubernetes.io/part-of=garuda pod label ([5ff4ed2](https://github.com/garuda-tunnel/wireguard-internal/commit/5ff4ed2e3af0b2dc23d007cd2e7cca00b751b1c9))
* **wireguard:** emit app.kubernetes.io/part-of=garuda pod label ([1fe90c2](https://github.com/garuda-tunnel/wireguard-internal/commit/1fe90c2bcb84c23d3f0d764d7314f94259ea0603))


### Bug Fixes

* **hub-k3s-cutover:** tag-correct transit provider + watcher fallback + smoke green ([#47](https://github.com/garuda-tunnel/wireguard-internal/issues/47)) ([4428088](https://github.com/garuda-tunnel/wireguard-internal/commit/4428088173cb68f92493a79dfa61466e835a7a9f))
* **hub-k3s-cutover:** tag-correct transit provider + watcher fallback + smoke green ([#47](https://github.com/garuda-tunnel/wireguard-internal/issues/47)) ([4428088](https://github.com/garuda-tunnel/wireguard-internal/commit/4428088173cb68f92493a79dfa61466e835a7a9f))
* **modules/charts:** exclude .terragrunt-source-manifest from Helm chart ([643850e](https://github.com/garuda-tunnel/wireguard-internal/commit/643850e301f90dfd7932edaea409c91c6c46e5c9))
* **phase2-border:** rely on CNI bridge ipMasq for border egress (revert WG_EGRESS_IFACE detour) ([407a0a7](https://github.com/garuda-tunnel/wireguard-internal/commit/407a0a73b86305321250d8a5d1646fd764fe8bf3))
* **phase2-edge-egress:** Multus pod RBAC + WG_NIC_ATTACH/WG_EGRESS_IFACE env + k3s-aware postup.sh ([46bf18f](https://github.com/garuda-tunnel/wireguard-internal/commit/46bf18f557bbe182d92b3b2dfeebeca2e18a4a5a))
* **wireguard/kube:** add NET_RAW + SYS_ADMIN to frr-sidecar capabilities ([1657bd0](https://github.com/garuda-tunnel/wireguard-internal/commit/1657bd00223c4274bf58438f3744c21b6d3467df))
* **wireguard/kube:** add peer.endpoint_listen_port so WG_PEER_ENDPOINT carries a port ([ad90188](https://github.com/garuda-tunnel/wireguard-internal/commit/ad9018861dc0ec5258a8dad4c612e1b18443c096))
* **wireguard/kube:** align deployment env vars with image entrypoint contract ([55a3f03](https://github.com/garuda-tunnel/wireguard-internal/commit/55a3f030f3eeb4f67682b886f2a888394d087c7d))

## [0.6.0](https://github.com/garuda-tunnel/wireguard-internal/compare/v0.5.0...v0.6.0) (2026-06-18)


### Features

* **wireguard:** align WG tunnel MTU (MTU/MSS Task 6) ([8d39e22](https://github.com/garuda-tunnel/wireguard-internal/commit/8d39e22de7581572f8800d92ce3f76d0a73b9251))
* **wireguard:** align WG tunnel MTU across both sides ([a8702ef](https://github.com/garuda-tunnel/wireguard-internal/commit/a8702ef702fcc0c125f43c412a7496835112357c))

## [0.5.0](https://github.com/garuda-tunnel/wireguard-internal/compare/v0.4.0...v0.5.0) (2026-06-17)


### Features

* **wireguard:** emit app.kubernetes.io/part-of=garuda pod label ([5ff4ed2](https://github.com/garuda-tunnel/wireguard-internal/commit/5ff4ed2e3af0b2dc23d007cd2e7cca00b751b1c9))
* **wireguard:** emit app.kubernetes.io/part-of=garuda pod label ([1fe90c2](https://github.com/garuda-tunnel/wireguard-internal/commit/1fe90c2bcb84c23d3f0d764d7314f94259ea0603))

## [0.4.0](https://github.com/garuda-tunnel/wireguard-internal/compare/v0.3.0...v0.4.0) (2026-06-16)


### Features

* **chart:** bump frr-sidecar dependency 0.1.0 -&gt; 0.2.0 ([bc5ffb9](https://github.com/garuda-tunnel/wireguard-internal/commit/bc5ffb9e49c48659e0de4bc6ddcdc8c8ed9341ce))
* **chart:** bump frr-sidecar dependency 0.1.0 → 0.2.0 ([cfc1662](https://github.com/garuda-tunnel/wireguard-internal/commit/cfc1662d60c9207feea5d0dca7219cb054c273b7))

## [0.3.0](https://github.com/garuda-tunnel/wireguard-internal/compare/v0.2.0...v0.3.0) (2026-06-16)


### Features

* pin wireguard image digest in chart (Phase 1) ([04d18f5](https://github.com/garuda-tunnel/wireguard-internal/commit/04d18f5be2f6e475d4df8d54baba29745580ef66))
* pin wireguard image digest in chart; TF conditional override; caller main-trigger + inputs ([3a79769](https://github.com/garuda-tunnel/wireguard-internal/commit/3a79769bc988aebdc662d307f7a466fe0e8d8211))
* wireguard tag-model publish (release-gated sync+publish, dev-image, chart .Chart.Version fallback) ([3ad4ebd](https://github.com/garuda-tunnel/wireguard-internal/commit/3ad4ebd82de3364bfba21889cb231ba5d8587279))
* wireguard tag-model publish (sub-project A) ([ed6a518](https://github.com/garuda-tunnel/wireguard-internal/commit/ed6a518be0be4ebe7be30a1fe657f3a70bab1620))
