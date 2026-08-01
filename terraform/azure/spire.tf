resource "helm_release" "spire_crds" {
  name             = "spire-crds"
  repository       = "https://spiffe.github.io/helm-charts-hardened/"
  chart            = "spire-crds"
  namespace        = "spire-server"
  create_namespace = false
  version          = "0.5.0"
}

resource "helm_release" "spire" {
  name             = "spire"
  repository       = "https://spiffe.github.io/helm-charts-hardened/"
  chart            = "spire"
  namespace        = "spire-server"
  create_namespace = false
  version          = "0.29.0"

  values = [
    yamlencode({
      global = {
        spire = {
          caSubject = {
            commonName   = "azure.bridgethegap.local"
            country      = "RO"
            organization = "BridgeTheGap"
          }
          clusterName = "bridge-the-gap-azure"
          namespaces = {
            server = {
              create = false
            }
            system = {
              create = true
            }
          }
          recommendations = {
            enabled = true
          }
          trustDomain = "azure.bridgethegap.local"
        }
      }
      "spiffe-oidc-discovery-provider" = {
        enabled = false
      }
      "spire-server" = {
        federation = {
          enabled = true
        }
        controllerManager = {
          identities = {
            clusterSPIFFEIDs = {
              default = {
                federatesWith = ["aws.bridgethegap.local"]
              }
            }
            clusterFederatedTrustDomains = {
              aws = {
                bundleEndpointProfile = {
                  endpointSPIFFEID = "spiffe://aws.bridgethegap.local/spire/server"
                  type             = "https_spiffe"
                }
                bundleEndpointURL = "https://af2f695436bee4333bb097f46666ac81-314184819.eu-central-1.elb.amazonaws.com:8443"
                trustDomain       = "aws.bridgethegap.local"
              }
            }
          }
        }
      }
    })
  ]

  depends_on = [helm_release.spire_crds]
}

resource "kubernetes_service" "spire_federation" {
  metadata {
    name      = "spire-server-federation-lb"
    namespace = "spire-server"
  }
  spec {
    selector = {
      "app.kubernetes.io/name"     = "server"
      "app.kubernetes.io/instance" = "spire"
    }
    port {
      name        = "federation"
      port        = 8443
      target_port = 8443
    }
    type = "LoadBalancer"
  }

  depends_on = [helm_release.spire]
}
