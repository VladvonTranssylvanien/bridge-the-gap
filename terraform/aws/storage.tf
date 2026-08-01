# Citește certificatul TLS al endpoint-ului OIDC al clusterului, ca să obținem
# thumbprint-ul necesar pentru înregistrarea providerului OIDC în IAM.
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Înregistrează clusterul EKS ca identity provider OIDC în IAM. Asta permite
# unui ServiceAccount din Kubernetes să "se autentifice" direct la AWS STS
# prin federare, fără nicio cheie de acces statică (IRSA).
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Trust policy: permite DOAR ServiceAccount-ului "ebs-csi-controller-sa" din
# namespace-ul "kube-system" să preia acest rol, nu orice pod din cluster.
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "bridge-the-gap-aws-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

# StorageClass nou, folosind provisioner-ul CSI real (nu vechiul "kubernetes.io/aws-ebs").
# Marcat default, ca orice PVC fără storageClassName explicit (inclusiv cele din
# chart-uri Helm terțe) să-l folosească automat.
resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}
