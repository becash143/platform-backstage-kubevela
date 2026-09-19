variable "kubeconfig_path" {
  description = "Path to kubeconfig file for the target cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use"
  type        = string
  default     = null
}

variable "kubevela_namespace" {
  description = "Namespace for KubeVela core + the Backstage bridge plugin"
  type        = string
  default     = "vela-system"
}

variable "kubevela_chart_version" {
  description = "KubeVela Helm chart version"
  type        = string
  default     = "1.9.11"
}

variable "backstage_namespace" {
  description = "Namespace for the Backstage portal"
  type        = string
  default     = "backstage"
}

variable "backstage_chart_version" {
  description = "Backstage Helm chart version"
  type        = string
  default     = "2.8.2"
}

variable "kubevela_plugin_image" {
  description = <<-EOT
    Container image for the backstage-plugin-kubevela backend
    (build from https://github.com/kubevela-contrib/backstage-plugin-kubevela
    and push to your own registry, see README).
  EOT
  type        = string
  default     = "ghcr.io/your-org/backstage-kubevela-plugin:latest"
}

variable "backstage_image" {
  description = "Your built Backstage app image (frontend + backend + kubevela plugin baked in)"
  type        = string
  default     = "ghcr.io/your-org/backstage-app:latest"
}

variable "backstage_base_url" {
  description = <<-EOT
    The real, externally-reachable URL Backstage will be served at
    (behind your Ingress/LoadBalancer), e.g. "https://backstage.example.com".
    No default on purpose: this must not silently fall back to a
    localhost value in a real deployment. Used for both app.baseUrl and
    backend.baseUrl, and backend.cors.origin is derived from it.
  EOT
  type        = string
}

variable "workload_namespace" {
  description = "Namespace where scaffolded KubeVela Applications (and thus the workloads Backstage needs read access to for the Kubernetes plugin) are deployed"
  type        = string
  default     = "default"
}

variable "kubevela_multicluster_enabled" {
  description = "Whether to enable KubeVela's multicluster (ClusterGateway) component. Requires a working Kubernetes API aggregation layer; disable on clusters where that isn't available (e.g. some local single-node setups)."
  type        = bool
  default     = true
}

variable "enable_kubernetes_plugin" {
  description = "Whether to wire up Backstage's Kubernetes plugin (live pod/deployment status on entity pages). Creates a dedicated read-only ServiceAccount + token for it."
  type        = bool
  default     = true
}
