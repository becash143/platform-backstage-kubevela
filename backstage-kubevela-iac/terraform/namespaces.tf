resource "kubernetes_namespace" "vela_system" {
  metadata {
    name = var.kubevela_namespace
    labels = {
      "app.kubernetes.io/part-of" = "platform"
    }
  }
}

resource "kubernetes_namespace" "backstage" {
  metadata {
    name = var.backstage_namespace
    labels = {
      "app.kubernetes.io/part-of" = "platform"
    }
  }
}
