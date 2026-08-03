# The AWS mesh currently has NO PeerAuthentication resource at all. Without
# one, Istio defaults to PERMISSIVE mode: every sidecar accepts both mTLS
# and plaintext connections. Azure's mesh has an explicit STRICT
# PeerAuthentication (see terraform/azure/istio-mtls.tf) - this brings the
# AWS side up to the same standard, closing an asymmetry in the two
# clusters' Istio-layer mesh security posture.
#
# This is a separate layer from the SPIFFE/SPIRE application-level mTLS
# used for the actual cross-cloud service-a -> service-b call (that one
# is enforced in each service's own Go code via go-spiffe, not by Istio).
# STRICT here only affects Istio's own sidecar-to-sidecar traffic on this
# cluster: istiod, kiali/prometheus scraping, ingress gateway internals.
resource "kubernetes_manifest" "peer_authentication_strict" {
  manifest = {
    apiVersion = "security.istio.io/v1"
    kind       = "PeerAuthentication"
    metadata = {
      name      = "default"
      namespace = "istio-system"
    }
    spec = {
      mtls = {
        mode = "STRICT"
      }
    }
  }
}
