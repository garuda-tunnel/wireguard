# Test harness: feeds the kube module keys that are unknown until apply, like
# the computed outputs of the tunnel module. Used by ../wireguard_kube.tftest.hcl.
resource "terraform_data" "private_key" {
  input = "unused"
}

resource "terraform_data" "preshared_key" {
  input = "unused"
}

module "kube" {
  source    = "../.."
  namespace = "garuda"
  name      = "wg-pt"

  self = {
    kernel_ifname = "wg-pt"
    private_key   = terraform_data.private_key.id
    address       = "192.0.2.2/30"
  }
  remote = {
    public_key    = "stubpublickey"
    endpoint_host = "hub.example.net"
    listen_port   = 55820
    preshared_key = terraform_data.preshared_key.output
  }
}

output "deployment_name" {
  value = module.kube.deployment_name
}
