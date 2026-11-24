mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  namespace = "garuda"
  name      = "wg-pt"

  self = {
    kernel_ifname = "wg-pt"
    private_key   = "stubprivatekey"
    address       = "192.0.2.2/30"
    listen_port   = null
  }

  remote = {
    public_key    = "stubpublickey"
    endpoint_host = "hub.example.net"
    listen_port   = 55820
    preshared_key = null
  }

  wireguard_image = "ghcr.io/alexmkx/garuda-wireguard:latest"
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
    condition     = helm_release.wireguard.version == "2.0.0"
    error_message = "helm_release.version must default to 2.0.0 from var.chart_version"
  }
}

# OpenTofu's yamlencode emits quoted block-style YAML ("key": "value").
run "values_map_self_and_remote" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"kernel_ifname\": \"wg-pt\"")
    error_message = "config.kernel_ifname must come from self"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"endpoint_host\": \"hub.example.net\"")
    error_message = "peer.endpoint_host must come from remote"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"listen_port\": 55820")
    error_message = "peer.listen_port must come from remote.listen_port"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"table\": \"off\"")
    error_message = "rendered values must contain table"
  }
}

run "no_removed_keys_rendered" {
  command = plan

  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"ospf\":")
    error_message = "ospf must not be rendered"
  }
  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"transit\":")
    error_message = "transit must not be rendered"
  }
  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"nic_attach\":")
    error_message = "nic_attach must not be rendered"
  }
  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"subnet\":")
    error_message = "config.subnet must not be rendered"
  }
}

run "allowed_nets_default_includes_multicast" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"0.0.0.0/0\"")
    error_message = "allowed_nets default must include 0.0.0.0/0"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"224.0.0.0/4\"")
    error_message = "allowed_nets default must include 224.0.0.0/4 (OSPF multicast)"
  }
}

run "remote_least_privilege_no_private_key_propagates" {
  # Passing a whole peer that HAS private_key SUCCEEDS (OpenTofu drops the extra
  # attribute — remote's type has no private_key). Assert it never reaches the
  # rendered helm values / secret path. This is NOT a rejection test.
  command = plan

  variables {
    remote = {
      public_key    = "stubpublickey"
      endpoint_host = "hub.example.net"
      listen_port   = 55820
      preshared_key = null
      private_key   = "REMOTE-PRIVATE-MUST-NOT-LEAK"
    }
  }

  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "REMOTE-PRIVATE-MUST-NOT-LEAK")
    error_message = "remote.private_key must never propagate into rendered values/state"
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
    self = {
      kernel_ifname = "wg-this-name-is-too-long"
      private_key   = "stubprivatekey"
      address       = "192.0.2.2/30"
      listen_port   = null
    }
  }

  expect_failures = [var.self]
}

# 51820/51821 are flannel wireguard-native's UDP ports on every k3s node; a
# tunnel hostPort there DNAT-steals flannel's packets, so both must be rejected.
run "self_flannel_wg_port_51820_rejected" {
  command = plan

  variables {
    self = {
      kernel_ifname = "wg-pt"
      private_key   = "stubprivatekey"
      address       = "192.0.2.2/30"
      listen_port   = 51820
    }
  }

  expect_failures = [var.self]
}

run "self_flannel_wg_port_51821_rejected" {
  command = plan

  variables {
    self = {
      kernel_ifname = "wg-pt"
      private_key   = "stubprivatekey"
      address       = "192.0.2.2/30"
      listen_port   = 51821
    }
  }

  expect_failures = [var.self]
}

# Any port other than 51820/51821 is valid. 51822 (not the remote fixture's
# 55820) proves the rendered listen_port comes from self.
run "self_nonstandard_listen_port_accepted" {
  command = plan

  variables {
    self = {
      kernel_ifname = "wg-pt"
      private_key   = "stubprivatekey"
      address       = "192.0.2.2/30"
      listen_port   = 51822
    }
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"listen_port\": 51822")
    error_message = "an allowed self.listen_port must plan and reach the rendered helm values"
  }
}

run "empty_wireguard_image_omits_images_key" {
  # With wireguard_image empty, local.images_override == {} so the rendered
  # helm values carry an empty images map. Helm deep-merges this no-op overlay
  # onto the chart's values.yaml, preserving the chart-pinned digest.
  command = plan

  variables {
    wireguard_image = ""
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"images\": {}")
    error_message = "with empty wireguard_image, rendered images must be an empty map so the chart's pinned digest wins"
  }
}

run "mtu_policy_default_site_mtu_1330" {
  command = plan

  assert {
    condition     = local.effective_mtu == 1330
    error_message = "mtu_policy default site_mtu must derive effective_mtu 1330"
  }
  assert {
    condition     = local.fixed_mss == 1290
    error_message = "mtu_policy default site_mtu must derive fixed_mss 1290"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"effectiveMtu\": 1330")
    error_message = "mtuPolicy.effectiveMtu must render 1330 from the default"
  }
  assert {
    condition     = !strcontains(helm_release.wireguard.values[0], "\"mtu\":")
    error_message = "legacy wireguard.mtu key must NOT be present"
  }
}

run "mtu_policy_explicit_override_honors_values" {
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
    condition     = strcontains(helm_release.wireguard.values[0], "\"effectiveMtu\": 1380")
    error_message = "explicit effective_mtu=1380 must appear as mtuPolicy.effectiveMtu"
  }
}

run "mtu_policy_reject_xor_violation" {
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
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"net.garuda-tunnel/router-id\": \"10.130.30.22\"")
    error_message = "podAnnotations must carry the injected router-id value"
  }
  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"net.garuda-tunnel/profile\": \"ospf-router\"")
    error_message = "podLabels must carry the injected profile label"
  }
  assert {
    condition     = length(kubernetes_config_map.garuda_extra) == 1 && contains(keys(kubernetes_config_map.garuda_extra), "wg-hub-ros-frr-extra")
    error_message = "one ConfigMap must be planned per configmaps entry, keyed by CM name"
  }
}
