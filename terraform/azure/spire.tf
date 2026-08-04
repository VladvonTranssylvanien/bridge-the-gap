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
              # See terraform/aws/spire.tf for the full rationale: this disables
              # the chart's catch-all "default" ClusterSPIFFEID (podSelector {},
              # fallback: true). service-b's identity comes from the dedicated
              # "istio-sidecar-reg" / "istio-ingressgateway-reg" entries below,
              # not from this fallback.
              default = {
                enabled       = false
                federatesWith = ["aws.bridgethegap.local"]
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

    # Restrict the federation bundle endpoint to the only source that has any
    # reason to reach it: the AWS cluster's NAT Gateway Elastic IP, which is
    # the egress address of the AWS SPIRE server fetching this trust bundle.
    #
    # Found during a post-delivery audit: this endpoint had no source
    # restriction at all and was reachable from the entire internet, while
    # service-b's LoadBalancer next to it was correctly locked to the same
    # single IP. The trust bundle itself is public information by design (it
    # is a set of root CA certificates, and the SPIFFE spec permits public
    # bundle endpoints), so this is not credential exposure. It is unnecessary
    # attack surface: an internet-reachable service with no legitimate
    # internet consumer, exposing version information and a DoS target.
    #
    # Same fragility as the hardcoded egress IP noted elsewhere in the README:
    # if the AWS NAT Gateway is recreated with a new EIP, bundle refresh
    # fails closed and this value must be updated alongside
    # aws_eip.nat in terraform/aws/network.tf.
    load_balancer_source_ranges = ["18.157.213.89/32"]
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
      federatesWith = ["aws.bridgethegap.local"]
    }
  }
}

resource "kubernetes_manifest" "istio_ingressgateway_reg" {
  manifest = {
    apiVersion = "spire.spiffe.io/v1alpha1"
    kind       = "ClusterSPIFFEID"
    metadata = {
      name = "istio-ingressgateway-reg"
    }
    spec = {
      # className scopes this ClusterSPIFFEID to our controller-manager instance.
      # spire-controller-manager only reconciles CRs whose className matches its
      # own --class-name flag (see helm values: controllerManager.className).
      # Without this, the controller silently ignores the CR (no error, no log)
      # and its GC loop removes any entry it doesn't recognize as its own.
      className = "spire-server-spire"
      # Without podSelector, this ClusterSPIFFEID has no scoping at all and the
      # controller reconciles it against every pod in the cluster, stamping the
      # same workloadSelectorTemplates onto each one regardless of that pod's
      # real identity. Those mismatched entries turned out to be harmless
      # (SPIRE requires ALL selectors on an entry to match a workload's real
      # attested selectors simultaneously, so a pod in the wrong namespace can
      # never satisfy them - the entries are inert), but they are still noise
      # and a sign the resource was underspecified. Scoping to the actual
      # ingress gateway pods via label match is the fix.
      podSelector = {
        matchLabels = {
          app = "istio-ingressgateway"
        }
      }
      spiffeIDTemplate = "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
      workloadSelectorTemplates = [
        "k8s:ns:istio-system",
        "k8s:sa:istio-ingressgateway",
      ]
    }
  }
}
