# This PeerAuthentication (mesh-wide STRICT mTLS) already exists live on
# this cluster, applied directly via kubectl during initial setup and
# never captured in Terraform - confirmed via the presence of a
# kubectl.kubernetes.io/last-applied-configuration annotation and zero
# matches for "PeerAuthentication" anywhere in this git repo. Same
# "apply but never commit" gap found earlier with the
# service-b-default-deny NetworkPolicy (see network-policy.tf).
#
# This resource is adopted into Terraform via `terraform import` so a
# rebuild from a clean checkout reproduces STRICT mTLS enforcement,
# instead of silently defaulting to Istio's own PERMISSIVE mode.
#
# STRICT means every sidecar in this mesh only accepts mTLS connections
# from other Istio-managed sidecars (using istiod's own CA, not the
# SPIFFE/SPIRE identities) - it protects mesh-internal traffic (istiod,
# kiali, prometheus scraping, ingress gateway internals). It is a
# separate layer from the application-level go-spiffe mTLS used for the
# actual cross-cloud service-a -> service-b call.
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
