mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  namespace = "garuda"
  name      = "wg-pt"

  config = {
    kernel_ifname = "wg-pt"
    private_key   = "stubprivatekey"
    address       = "192.0.2.2/30"
    subnet        = "192.0.2.0/30"
    listen_port   = null
    endpoint_host = null
  }

  peer = {
    public_key           = "stubpublickey"
    endpoint_host        = "hub.example.net"
    endpoint_listen_port = 51820
    preshared_key        = null
    address              = "192.0.2.1/30"
  }

  allowed_nets    = ["0.0.0.0/0"]
  wireguard_image = "ghcr.io/alexmkx/garuda-wireguard:latest"
  mtu_policy = {
    site_mtu = 1330
  }
}

run "chart_resolves_from_oci" {
  command = plan

  assert {
    condition     = helm_release.wireguard.repository == "oci://ghcr.io/garuda-tunnel/charts"
    error_message = "helm_release.repository must be the garuda OCI charts registry"
  }
  assert {
    condition     = helm_release.wireguard.chart == "wireguard"
    error_message = "helm_release.chart must be the OCI chart name 'wireguard'"
  }
  assert {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", helm_release.wireguard.version))
    error_message = "helm_release.version must be an exact semver from var.chart_version"
  }
}

# OpenTofu's yamlencode emits quoted block-style YAML ("key": "value"),
# so substrings below match that form. See modules/garuda_k8s/tests/garuda_k8s.tftest.hcl
# for the precedent set in Task 5.
run "values_include_peer_and_config" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"kernel_ifname\": \"wg-pt\"")
    error_message = "rendered values must contain config.kernel_ifname"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"endpoint_host\": \"hub.example.net\"")
    error_message = "rendered values must contain peer.endpoint_host"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"table\": \"off\"")
    error_message = "rendered values must contain table"
  }
}

run "default_ospf_is_null" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"ospf\": null")
    error_message = "with default var.ospf=null, rendered values must contain 'ospf: null'"
  }
}

run "ospf_set_propagates_router_id_and_interfaces" {
  command = plan

  variables {
    ospf = {
      router_id  = "10.130.30.1"
      interfaces = ["wg-pt"]
    }
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"router_id\": \"10.130.30.1\"")
    error_message = "rendered values must contain ospf.router_id"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "- \"wg-pt\"")
    error_message = "rendered values must contain ospf.interfaces entry"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"default_originate\": false")
    error_message = "ospf.default_originate must default to false"
  }
}

run "nic_attach_default_is_backbone_and_border" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "- \"backbone\"")
    error_message = "default nic_attach must include backbone"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "- \"border\"")
    error_message = "default nic_attach must include border"
  }
}

run "deployment_name_output" {
  command = plan

  assert {
    condition     = output.deployment_name == "wg-pt"
    error_message = "output.deployment_name must equal var.name"
  }
}

run "invalid_ifname_too_long_rejected" {
  command = plan

  variables {
    config = {
      kernel_ifname = "wg-this-name-is-too-long"
      private_key   = "stubprivatekey"
      address       = "192.0.2.2/30"
      subnet        = "192.0.2.0/30"
      listen_port   = null
      endpoint_host = null
    }
  }

  expect_failures = [var.config]
}

run "invalid_ospf_router_id_rejected" {
  command = plan

  variables {
    ospf = {
      router_id  = "not-an-ip"
      interfaces = ["wg-pt"]
    }
  }

  expect_failures = [var.ospf]
}

run "invalid_ospf_redistribute_value_rejected" {
  command = plan

  variables {
    ospf = {
      router_id    = "10.130.30.1"
      interfaces   = ["wg-pt"]
      redistribute = ["bgp"]
    }
  }

  expect_failures = [var.ospf]
}

run "empty_wireguard_image_omits_images_key" {
  # With wireguard_image empty, local.images_override == {} so the rendered
  # helm values carry an empty images map. Helm deep-merges this no-op overlay
  # onto the chart's values.yaml, preserving the chart-pinned digest.
  # frr_image is kept inert (Phase 4+5 Decision #5) and does not contribute
  # any key to images regardless of its value.
  command = plan

  variables {
    wireguard_image = ""
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"images\": {}")
    error_message = "with empty wireguard_image, rendered images must be an empty map so the chart's pinned digest wins"
  }
}

run "mtu_policy_propagates_to_mtu_policy_helm_values" {
  # mtu_policy.site_mtu must derive effective_mtu, fixed_mss, mss_clamp_enabled
  # and appear under mtuPolicy.* in helm values. No legacy wireguard.mtu key.
  command = plan

  variables {
    mtu_policy = {
      site_mtu = 1330
    }
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"effectiveMtu\": 1330")
    error_message = "mtu_policy.site_mtu must propagate effectiveMtu=1330 under mtuPolicy in helm values"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"fixedMss\": 1290")
    error_message = "mtu_policy.site_mtu=1330 must derive fixedMss=1290 under mtuPolicy in helm values"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"mssClampEnabled\": true")
    error_message = "default mss_clamp_enabled=true must appear under mtuPolicy in helm values"
  }

  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"mtu\":")
    error_message = "legacy wireguard.mtu key must NOT be present in rendered helm values"
  }
}

run "mtu_policy_site_mtu_derives_values" {
  command = plan

  variables {
    mtu_policy = {
      site_mtu = 1330
    }
  }

  assert {
    condition     = local.effective_mtu == 1330
    error_message = "site_mtu must derive effective_mtu 1330"
  }

  assert {
    condition     = local.fixed_mss == 1290
    error_message = "site_mtu 1330 must derive fixed_mss 1290"
  }
}

run "mtu_policy_explicit_override_honors_values" {
  # explicit override: effective_mtu=1380, fixed_mss=1340 must pass through unchanged.
  command = plan

  variables {
    mtu_policy = {
      effective_mtu = 1380
      fixed_mss     = 1340
    }
  }

  assert {
    condition     = local.effective_mtu == 1380
    error_message = "explicit effective_mtu=1380 must be honored"
  }

  assert {
    condition     = local.fixed_mss == 1340
    error_message = "explicit fixed_mss=1340 must be honored"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"effectiveMtu\": 1380")
    error_message = "explicit effective_mtu=1380 must appear as mtuPolicy.effectiveMtu in helm values"
  }
}

run "mtu_policy_reject_xor_violation" {
  # Passing both site_mtu and effective_mtu violates the XOR constraint.
  command = plan

  variables {
    mtu_policy = {
      site_mtu      = 1330
      effective_mtu = 1280
    }
  }

  expect_failures = [var.mtu_policy]
}

run "nonempty_wireguard_image_overrides" {
  # A non-empty wireguard_image must flow into images.wireguard (overriding the
  # chart default). images.frr is never emitted regardless of frr_image
  # (Phase 4+5 Decision #5: frr-sidecar is MAP-owned, not chart-owned).
  command = plan

  variables {
    wireguard_image = "ghcr.io/garuda-tunnel/garuda-wireguard@sha256:1111111111111111111111111111111111111111111111111111111111111111"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"wireguard\": \"ghcr.io/garuda-tunnel/garuda-wireguard@sha256:1111111111111111111111111111111111111111111111111111111111111111\"")
    error_message = "non-empty wireguard_image must appear under images.wireguard"
  }

  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"frr\":")
    error_message = "images.frr must never appear in rendered helm values (frr-sidecar is MAP-owned)"
  }
}

run "passthrough_annotations_labels_configmaps" {
  command = plan
  variables {
    annotations = { "net.garuda-tunnel/router-id" = "10.130.30.22" }
    labels      = { "net.garuda-tunnel/profile" = "ospf-router" }
    configmaps  = { "wg-hub-ros-frr-extra" = { "extra.conf" = "ip forwarding" } }
  }
  # Assert on the injected VALUE, not just the key name (a `podAnnotations: {}`
  # default would pass a bare key-name substring and give false confidence).
  # yamlencode emits quoted JSON-style YAML ("key": "value") — match that format.
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"net.garuda-tunnel/router-id\": \"10.130.30.22\"")
    error_message = "podAnnotations must carry the injected router-id value"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"net.garuda-tunnel/profile\": \"ospf-router\"")
    error_message = "podLabels must carry the injected profile label"
  }
  # Count is robust under bare mock_provider (metadata[0].name may be a synthetic
  # placeholder; the instance-key set is what we assert).
  assert {
    condition     = length(kubernetes_config_map.garuda_extra) == 1 && contains(keys(kubernetes_config_map.garuda_extra), "wg-hub-ros-frr-extra")
    error_message = "one ConfigMap must be planned per configmaps entry, keyed by CM name"
  }
}
