resource "helm_release" "spire_crds" {
  name             = "spire-crds"
  repository       = "https://spiffe.github.io/helm-charts-hardened/"
  chart            = "spire-crds"
  namespace        = "spire-server"
  create_namespace = true
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
            commonName   = "aws.bridgethegap.local"
            country      = "RO"
            organization = "BridgeTheGap"
          }
          clusterName = "bridge-the-gap-aws"
          namespaces = {
            server = {
              create = false
            }
            system = {
              create = true
            }
          }
          persistence = {
            storageClass = "ebs-gp3"
          }
          recommendations = {
            enabled = true
          }
          trustDomain = "aws.bridgethegap.local"
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
                federatesWith = ["azure.bridgethegap.local"]
              }
            }
            clusterFederatedTrustDomains = {
              azure = {
                bundleEndpointProfile = {
                  endpointSPIFFEID = "spiffe://azure.bridgethegap.local/spire/server"
                  type             = "https_spiffe"
                }
                bundleEndpointURL = "https://51.105.114.140:8443"
                trustDomain       = "azure.bridgethegap.local"
              }
            }
          }
        }
      }
    })
  ]

  depends_on = [helm_release.spire_crds, kubernetes_storage_class.ebs_gp3]
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

resource "kubernetes_manifest" "istio_sidecar_reg" {
  manifest = {
    apiVersion = "spire.spiffe.io/v1alpha1"
    kind       = "ClusterSPIFFEID"
    metadata = {
      name = "istio-sidecar-reg"
    }
    spec = {
      podSelector = {
        matchLabels = {
          "spiffe.io/spire-managed-identity" = "true"
        }
      }
      spiffeIDTemplate = "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
    }
  }
}
