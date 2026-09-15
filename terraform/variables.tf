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
    and push to your own registry — see README).
  EOT
  type        = string
  default     = "ghcr.io/your-org/backstage-kubevela-plugin:latest"
}

variable "backstage_image" {
  description = "Your built Backstage app image (frontend + backend + kubevela plugin baked in)"
  type        = string
  default     = "ghcr.io/your-org/backstage-app:latest"
}
