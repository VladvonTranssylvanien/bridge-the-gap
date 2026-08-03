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
        defaultX509SvidTTL = "30m"
        federation = {
          enabled = true
        }
        controllerManager = {
          # Pinned explicitly instead of relying on the chart's implicit
          # defaults. className defaults to "{Release.Namespace}-{Release.Name}"
          # ("spire-server-spire" here) when left empty, and watchClassless
          # defaults to false. Both of our own ClusterSPIFFEID resources
          # (istio_sidecar_reg, istio_ingressgateway_reg) already hardcode
          # className = "spire-server-spire" to match. Pinning both values
          # here removes the implicit coupling: if a future chart upgrade
          # ever changes either default, our CRs keep reconciling instead of
          # being silently ignored again (see item 10 in the README's
          # Security Hardening & Trade-offs section for the incident this
          # class of bug caused).
          className      = "spire-server-spire"
          watchClassless = false
          identities = {
            clusterSPIFFEIDs = {
              # The chart's built-in "default" ClusterSPIFFEID is a catch-all:
              # podSelector {} (matches every pod) + fallback: true, meaning it
              # issues an identity to ANY pod in a non-system namespace, not
              # just service-a. Our actual workloads get their identity from
              # the dedicated "istio-sidecar-reg" ClusterSPIFFEID below, scoped
              # to pods labeled spiffe.io/spire-managed-identity=true. Disabling
              # "default" removes the unused catch-all without affecting
              # service-a's identity issuance (verified: no other component
              # depends on the fallback path).
              default = {
                enabled       = false
                federatesWith = ["azure.bridgethegap.local"]
              }
              # None of these chart-shipped identity types are used by this
              # project (no SPIKE secrets-management components, no OIDC
              # discovery provider deployment - that subchart is already
              # disabled above - and no test-keys/child-servers usage). Each
              # defaults to enabled=true in the chart regardless of whether
              # the underlying component is deployed, so a real pod never
              # attests them, but disabling them removes the unused entries
              # and matches the same "no unused catch-alls" principle as the
              # disabled "default" fallback above.
              "oidc-discovery-provider" = {
                enabled = false
              }
              "test-keys" = {
                enabled = false
              }
              "spike-keeper" = {
                enabled = false
              }
              "spike-nexus" = {
                enabled = false
              }
              "spike-bootstrap" = {
                enabled = false
              }
              "spike-pilot" = {
                enabled = false
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
      # className scopes this ClusterSPIFFEID to our controller-manager instance.
      # spire-controller-manager only reconciles CRs whose className matches its
      # own --class-name flag (see helm values: controllerManager.className).
      # Without this, the controller silently ignores the CR (no error, no log)
      # and its GC loop removes any entry it doesn't recognize as its own.
      className = "spire-server-spire"
      podSelector = {
        matchLabels = {
          "spiffe.io/spire-managed-identity" = "true"
        }
      }
      spiffeIDTemplate = "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
      # federatesWith establishes the cross-cloud trust: this workload's local
      # spire-agent will fetch and cache the named trust domain's bundle so the
      # app's go-spiffe X509Source can validate the peer's certificate chain.
      federatesWith = ["azure.bridgethegap.local"]
    }
  }
}
