# ---- Dedicated ServiceAccount ----
# Created by Terraform (not the Helm chart's serviceAccount.create) so
# RBAC bindings below have a stable, known name to target regardless of
# Helm chart defaults. helm-values.yaml.tpl sets serviceAccount.create
# to false and serviceAccount.name to this account's name.
resource "kubernetes_service_account" "backstage" {
  metadata {
    name      = "backstage"
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }
}

# ---- Backend signing key ----
# Recent Backstage backends require a signing key under
# backend.auth.keys or the backend refuses to start.
resource "random_password" "backstage_backend_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "backstage_backend" {
  metadata {
    name      = "backstage-backend-secret"
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }

  data = {
    BACKEND_SECRET = random_password.backstage_backend_secret.result
  }
}

# ---- Postgres credentials ----
# Generated, not hardcoded. Referenced via postgresql.auth.existingSecret
# in helm-values.yaml.tpl so the password never appears in the rendered
# values or in git. Bitnami's postgresql subchart expects the keys
# "postgres-password" and "password" specifically when existingSecret
# is used with both an admin and an application user.
resource "random_password" "postgres_admin" {
  length  = 32
  special = false
}

resource "random_password" "postgres_app" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "backstage_postgres" {
  metadata {
    name      = "backstage-postgres-credentials"
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }

  data = {
    "postgres-password" = random_password.postgres_admin.result
    "password"           = random_password.postgres_app.result
  }
}

# ---- Kubernetes plugin token (optional) ----
# Long-lived token for the dedicated ServiceAccount above, used by
# Backstage's Kubernetes plugin to show live pod/deployment status on
# entity pages. Kept in its own Secret and injected via
# extraEnvVarsSecrets, never as a literal in helm-values.yaml.tpl.
#
# CAVEAT: this relies on the legacy auto-populated service-account-token
# Secret mechanism, which some newer/managed Kubernetes distributions
# have disabled by default (it was deprecated starting Kubernetes 1.24).
# If `terraform apply` hangs waiting on this resource, your cluster
# likely has it disabled; see the README for the `kubectl create token`
# fallback.
resource "kubernetes_secret" "backstage_k8s_token" {
  count = var.enable_kubernetes_plugin ? 1 : 0

  metadata {
    name      = "backstage-k8s-token"
    namespace = kubernetes_namespace.backstage.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.backstage.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"

  wait_for_service_account_token = true
}

resource "helm_release" "backstage" {
  name             = "backstage"
  repository       = "https://backstage.github.io/charts"
  chart            = "backstage"
  version          = var.backstage_chart_version
  namespace        = kubernetes_namespace.backstage.metadata[0].name
  create_namespace = false

  values = [
    templatefile("${path.module}/../backstage/helm-values.yaml.tpl", {
      backstage_image          = var.backstage_image
      backstage_base_url       = var.backstage_base_url
      kubevela_plugin_host     = "http://${kubernetes_service.kubevela_plugin.metadata[0].name}.${kubernetes_namespace.vela_system.metadata[0].name}.svc.cluster.local:8080"
      backend_secret_name      = kubernetes_secret.backstage_backend.metadata[0].name
      postgres_secret_name     = kubernetes_secret.backstage_postgres.metadata[0].name
      service_account_name     = kubernetes_service_account.backstage.metadata[0].name
      enable_kubernetes_plugin = var.enable_kubernetes_plugin
      k8s_token_secret_name    = var.enable_kubernetes_plugin ? kubernetes_secret.backstage_k8s_token[0].metadata[0].name : ""
    })
  ]

  depends_on = [
    kubernetes_service.kubevela_plugin,
    helm_release.kubevela,
    kubernetes_secret.backstage_backend,
    kubernetes_secret.backstage_postgres,
    kubernetes_service_account.backstage,
  ]
}
