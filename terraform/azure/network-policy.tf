resource "kubernetes_network_policy_v1" "service_b_default_deny" {
  metadata {
    name      = "service-b-default-deny"
    namespace = "workloads"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "service-b"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      ports {
        port     = 8080
        protocol = "TCP"
      }
      from {
        ip_block {
          cidr = "10.1.1.0/24"
        }
      }
    }

    # Allows Prometheus (namespace "monitoring") to scrape the Envoy
    # sidecar's merged stats endpoint (istio-proxy exposes app + Envoy
    # metrics together on 15020). Without this rule, NetworkPolicy's
    # default-deny silently blocks Prometheus from ever reaching this
    # pod - the actual mTLS traffic and AuthorizationPolicy enforcement
    # work fine regardless, but Kiali's mesh graph and mTLS visualization
    # stay empty because their only metrics source here is unreachable.
    ingress {
      ports {
        port     = 15020
        protocol = "TCP"
      }
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "monitoring"
          }
        }
      }
    }

    egress {
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
    }

    egress {
      ports {
        port     = 15012
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "istio-system"
          }
        }
        pod_selector {
          match_labels = {
            app = "istiod"
          }
        }
      }
    }
  }
}
