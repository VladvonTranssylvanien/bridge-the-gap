resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
  }
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = var.istio_version
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = var.istio_version
  namespace  = kubernetes_namespace.istio_system.metadata[0].name

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingressgateway" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = var.istio_version
  namespace  = kubernetes_namespace.istio_system.metadata[0].name

  depends_on = [helm_release.istiod]
}
