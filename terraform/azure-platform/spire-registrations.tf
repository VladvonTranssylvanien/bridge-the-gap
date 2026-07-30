resource "null_resource" "istio_spire_registrations" {
  triggers = {
    manifest_sha = filesha256("${path.module}/manifests/clusterspiffeid-istio.yaml")
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/manifests/clusterspiffeid-istio.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -f ${path.module}/manifests/clusterspiffeid-istio.yaml --ignore-not-found=true"
  }

  depends_on = [helm_release.spire]
}
