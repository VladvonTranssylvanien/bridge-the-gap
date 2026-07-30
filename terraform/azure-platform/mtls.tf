resource "null_resource" "mesh_strict_mtls" {
  triggers = {
    manifest_sha = filesha256("${path.module}/manifests/peer-authentication-strict.yaml")
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/manifests/peer-authentication-strict.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -f ${path.module}/manifests/peer-authentication-strict.yaml --ignore-not-found=true"
  }

  depends_on = [helm_release.istiod]
}
