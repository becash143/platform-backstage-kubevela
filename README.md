# Backstage + KubeVela Platform (IaC, GitOps-ready)

Terraform that installs and wires together **KubeVela** (application delivery on Kubernetes) and **Backstage** (the developer-facing catalog/portal), so KubeVela Applications automatically sync into the Backstage software catalog, and new services created through Backstage flow out through a real GitOps path (git commit → reconciler applies it), not a direct in-cluster apply.

Cloud agnostic: targets any existing multi-node cluster via kubeconfig (EKS, GKE, AKS, self-managed, etc.). No cloud-specific provisioning is included; bring your own cluster.

This is the production-oriented version of this project. If you're testing locally on a single-node cluster (Docker Desktop, kind, minikube), several defaults here (a real `backstage_base_url`, a real GitHub integration for the scaffolder template, an external reconciler) won't apply the same way; see [Local/single-node notes](#localsingle-node-notes) at the bottom.

---

## Table of contents

- [What this deploys](#what-this-deploys)
- [Repository layout](#repository-layout)
- [Everything you need to do first](#everything-you-need-to-do-first)
- [Required: an external GitOps reconciler](#required-an-external-gitops-reconciler)
- [Deploy with Terraform](#deploy-with-terraform)
- [Terraform variables](#terraform-variables)
- [Verify the bridge is working](#verify-the-bridge-is-working)
- [Golden path for new services](#golden-path-for-new-services)
- [The Kubernetes plugin (live pod status)](#the-kubernetes-plugin-live-pod-status)
- [Configuration notes](#configuration-notes)
- [Known gaps this doesn't solve](#known-gaps-this-doesnt-solve)
- [Troubleshooting](#troubleshooting)
- [Local/single-node notes](#localsingle-node-notes)

---

## What this deploys

| Component | What it is | Where it runs |
|---|---|---|
| KubeVela (`vela-core`) | OAM-based application delivery engine | `vela-system` namespace |
| Bridge plugin (`backstage-plugin-kubevela`) | Community connector that reads KubeVela `Application` resources and serves them to Backstage | `vela-system` namespace |
| Backstage | Developer-facing catalog and portal | `backstage` namespace |

The bridge plugin polls the Kubernetes API for `Application` resources (read-only, scoped RBAC) and exposes them over HTTP. Backstage's catalog provider polls that endpoint on a schedule and mirrors what it finds into the software catalog as entities. That direction, cluster → catalog, is fully automated and doesn't involve git at all.

The other direction, creating a *new* service from Backstage, does go through git: the scaffolder template pushes generated files (including a KubeVela `Application` manifest) to a new GitHub repo, and it's your GitOps reconciler (ArgoCD, Flux, etc., not included here) that actually applies it to the cluster. See [Required: an external GitOps reconciler](#required-an-external-gitops-reconciler).

---

## Repository layout

```
terraform/                    Cluster-side infra: Helm releases, namespaces, RBAC, plugin Deployment
backstage/
  helm-values.yaml.tpl         Templated Helm values: vela provider, backend auth, Postgres, Kubernetes plugin
  catalog-plugin-wiring.ts     Code you must add to your own Backstage app source (see below)
scaffolder-templates/
  oam-service/                 Golden-path template: scaffolds a new service + Vela Application, publishes to GitHub
examples/sample-app/           Working reference: catalog-info.yaml + Application manifest
```

---

## Everything you need to do first

This repo automates the cluster-side infrastructure. It does **not** and **cannot** automate the items below, because they require compiling custom code into container images, or setting up systems (GitHub integration, a reconciler) outside this repo's scope, before Terraform ever runs.

### 1. Build your Backstage app image

Terraform deploys a pre-built Backstage container image (`var.backstage_image`). It has no way to modify the source code that image was built from, so the entity-provider wiring has to be in the image before you push it.

| Step | Command / action |
|---|---|
| Scaffold a Backstage app (if you don't already have one) | `npx @backstage/create-app@latest` |
| Install the plugin package | `yarn --cwd packages/backend add @oamdev/plugin-kubevela-backend` |
| Wire the provider into the catalog backend | Add [`backstage/catalog-plugin-wiring.ts`](backstage/catalog-plugin-wiring.ts) as `packages/backend/src/modules/vela.ts`, and add `backend.add(import('./modules/vela'));` to `packages/backend/src/index.ts` |
| Install a real sign-in provider | `dangerouslyDisableDefaultAuthPolicy` is deliberately **not** set in `helm-values.yaml.tpl`. Wire GitHub/Google/OIDC (or at minimum the guest provider) in your app's `index.ts`, or every API call will 401. |
| Copy the static catalog examples in | Copy `examples/sample-app/` (and, if you want the golden-path template discoverable, `scaffolder-templates/oam-service/`) into your app's own `examples/` directory so your Dockerfile's `COPY examples ./examples` step picks them up |
| Build the image | `docker build -f packages/backend/Dockerfile -t <your-registry>/backstage-app:<tag> .` |
| Push it | Push to your CI-managed registry, tagged by git SHA, not a manually-run local tag |
| Use it | Pass the pushed tag as `var.backstage_image` |

`catalog-plugin-wiring.ts` targets the **new** backend system (`backend.add(...)` in a single `index.ts`), which is what `create-app@latest` scaffolds today. If your app still uses the older plugin-file pattern, the same file has that variant commented at the bottom.

### 2. Build the KubeVela bridge plugin image

| Step | Command / action |
|---|---|
| Clone the connector repo | `git clone https://github.com/kubevela-contrib/backstage-plugin-kubevela` |
| Build the image | `docker build -t <your-registry>/backstage-kubevela-plugin:<tag> .` |
| Push it | Same CI-managed registry as above |
| Use it | Pass the pushed tag as `var.kubevela_plugin_image` |

### 3. Point kubectl at your target cluster

Make sure a valid kubeconfig context exists for the cluster you're deploying to. Pass these as `var.kubeconfig_path` / `var.kube_context` (defaults: `~/.kube/config` and the current context).

### 4. Set a real `backstage_base_url`

There's deliberately no default for `var.backstage_base_url`. It needs to be the real, externally-reachable URL Backstage will be served at (e.g. `https://backstage.internal.example.com`), behind whatever Ingress/LoadBalancer you're using. Set `ingress.enabled: true` in `helm-values.yaml.tpl` and configure a host/TLS block matching it once you have a real Ingress controller and DNS record.

### 5. Set up GitHub integration in Backstage

The default scaffolder template (`scaffolder-templates/oam-service/template.yaml`) uses `publish:github`, which needs a GitHub integration configured in your app's `app-config.yaml` (`integrations.github`, with a token that can create repos in your target org). This isn't something Terraform can set up, it's app-level config baked into the image alongside the catalog wiring.

---

## Required: an external GitOps reconciler

This repo intentionally does **not** install ArgoCD, Flux, or any reconciler. The scaffolder template pushes a new repo containing a KubeVela `Application` manifest; something needs to actually apply that manifest to the cluster on an ongoing basis. Point an existing ArgoCD/Flux instance at the repos this template creates (or the org/pattern they follow), or install one before relying on the golden path in this repo to actually deploy anything.

Without a reconciler watching, running the template will successfully create a GitHub repo and register a Backstage catalog entity, but nothing will actually run on the cluster.

---

## Deploy with Terraform

Once the images from steps 1-2 are built and pushed, and you have a real `backstage_base_url`:

```bash
cd terraform
terraform init
terraform apply \
  -var="kubevela_plugin_image=<your-registry>/backstage-kubevela-plugin:<tag>" \
  -var="backstage_image=<your-registry>/backstage-app:<tag>" \
  -var="backstage_base_url=https://backstage.internal.example.com"
```

This creates:

- **`vela-system` namespace**: KubeVela core, the bridge plugin (Deployment + Service), and RBAC scoped to read-only access on `Application` resources
- **`backstage` namespace**: Backstage, a dedicated ServiceAccount, generated backend/Postgres secrets, RBAC for that ServiceAccount, and `vela.host` pointed at the in-cluster plugin service

---

## Terraform variables

| Variable | Description | Default |
|---|---|---|
| `kubeconfig_path` | Path to kubeconfig file for the target cluster | `~/.kube/config` |
| `kube_context` | kubeconfig context to use | `null` (current context) |
| `kubevela_namespace` | Namespace for KubeVela core + the bridge plugin | `vela-system` |
| `kubevela_chart_version` | KubeVela Helm chart version | `1.9.11` |
| `kubevela_multicluster_enabled` | Enable KubeVela's ClusterGateway component. Needs a working API aggregation layer; most managed multi-node clusters have this. | `true` |
| `backstage_namespace` | Namespace for the Backstage portal | `backstage` |
| `backstage_chart_version` | Backstage Helm chart version | `2.8.2` |
| `backstage_base_url` | **Required, no default.** Real externally-reachable URL for Backstage | none |
| `workload_namespace` | Namespace where scaffolded KubeVela Applications get deployed | `default` |
| `enable_kubernetes_plugin` | Wire up live pod/deployment status on entity pages | `true` |
| `kubevela_plugin_image` | Your pushed bridge plugin image | `ghcr.io/your-org/backstage-kubevela-plugin:latest` |
| `backstage_image` | Your pushed Backstage app image | `ghcr.io/your-org/backstage-app:latest` |

---

## Verify the bridge is working

```bash
kubectl apply -f examples/sample-app/application.yaml
```

Open Backstage at your configured `backstage_base_url` and check the catalog for `hello-service`. It should appear as a Component within one refresh interval (default 30s), sourced from the live Application.

---

## Golden path for new services

Load `scaffolder-templates/oam-service/template.yaml` into Backstage's software templates (via a `catalog.locations` entry pointing at it, same mechanism as `examples/sample-app`). It scaffolds a new repo containing:

- `catalog-info.yaml` with the annotations the provider reads (`kubevela.io/application`, `kubevela.io/namespace`)
- `vela-application.yaml` with a minimal `webservice` component and traits

...pushes that repo to GitHub via `publish:github`, then registers it in the catalog. Actually getting it running on the cluster is your GitOps reconciler's job, see [Required: an external GitOps reconciler](#required-an-external-gitops-reconciler).

---

## The Kubernetes plugin (live pod status)

When `enable_kubernetes_plugin = true` (the default), Terraform creates a dedicated read-only ServiceAccount and a token Secret for it, and `helm-values.yaml.tpl` wires that token into Backstage's `kubernetes:` config so entity pages can show a live pod/deployment status tab.

**This needs matching app-side changes too**, Terraform can't install frontend packages into your image:
- Add `@backstage/plugin-kubernetes` to `packages/app`
- Add it as a feature (new frontend system) or to your `EntityPage` (old frontend system)
- Your KubeVela-synthesized entities need to actually carry an annotation the plugin can match against pods by (e.g. a label selector); check what `VelaProvider` forwards from the Application manifest's own annotations before assuming this "just works" end to end

**Compatibility caveat**: `kubernetes_secret.backstage_k8s_token` relies on the legacy auto-populated service-account-token Secret mechanism, deprecated since Kubernetes 1.24 and disabled outright on some newer/managed distributions. If `terraform apply` hangs on that resource, your cluster doesn't support it; set `enable_kubernetes_plugin = false` and instead mint a token manually (`kubectl create token backstage -n backstage --duration=<your rotation window>`), store it in a Secret yourself, and reference that Secret's name via a `-var` override until this repo has a better fallback for that case.

---

## Configuration notes

**Provider config path.** `catalog-plugin-wiring.ts` (new backend system) reads its config from a flat `vela:` block at the root of app-config, not from `catalog.providers.vela.<id>` (a different integration path this repo doesn't use). `helm-values.yaml.tpl` and the wiring code are kept in sync on this.

**Backend auth.** Recent Backstage backends require a signing key under `backend.auth.keys` to start. Terraform generates one and injects it via a Kubernetes Secret and `extraEnvVarsSecrets`.

**Postgres.** Credentials are Terraform-generated (`random_password`) and referenced via `postgresql.auth.existingSecret`, never a literal in `helm-values.yaml.tpl`. Bitnami's chart expects `password`/`postgres-password` as the secret keys when `existingSecret` is set, which is what `backstage.tf` creates. For anything beyond a demo, consider an externally-managed Postgres (RDS/Cloud SQL) instead of the in-cluster subchart.

**ServiceAccount.** Backstage runs under a Terraform-created, dedicated `backstage` ServiceAccount (`serviceAccount.create: false` + an explicit name in the Helm values), not the namespace's shared `default` account. RBAC in `backstage-rbac.tf` binds to that specific name.

---

## Known gaps this doesn't solve

| Gap | Detail |
|---|---|
| RBAC is still two systems | Backstage permissions and Kubernetes/KubeVela RBAC are configured independently; there's no single source of truth for "who can do what" |
| Polling, not push | Status is only as fresh as the refresh interval; the community plugin has no webhook/event-driven sync as of this writing |
| Multi-cluster isn't handled | This wiring assumes one cluster. KubeVela supports multi-cluster delivery; extending the provider to multiple `host` entries is the natural next step |
| No reconciler included | See [Required: an external GitOps reconciler](#required-an-external-gitops-reconciler) |

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Catalog never shows the entity | `var.backstage_image` was not rebuilt with `catalog-plugin-wiring.ts` baked in |
| Backstage backend won't start | Missing/misconfigured `backend.auth.keys`, or `backstage_base_url` mismatched against how you're actually reaching it (CORS) |
| Every request 401s | No real sign-in provider wired into the app's `index.ts`; `dangerouslyDisableDefaultAuthPolicy` is deliberately not set here |
| Entity appears once, then goes stale | `catalog-info.yaml` is missing the `kubevela.io/application` / `kubevela.io/namespace` annotations |
| Provider can't reach the plugin | Confirm `vela.host` in the rendered Helm values matches the in-cluster Service DNS name, and `backend.reading.allow` includes that host |
| `terraform apply` hangs on `kubernetes_secret.backstage_k8s_token` | Your cluster has disabled legacy service-account-token Secrets; see [The Kubernetes plugin](#the-kubernetes-plugin-live-pod-status) |
| Template runs successfully but nothing deploys | Expected, no reconciler is included; see [Required: an external GitOps reconciler](#required-an-external-gitops-reconciler) |

---

## Local/single-node notes

If you're testing on Docker Desktop, kind, or minikube rather than a real multi-node cluster:

- `kubevela_multicluster_enabled = false` is usually needed, single-node clusters often can't satisfy KubeVela's ClusterGateway aggregation-layer requirement.
- `backstage_base_url` can be `http://localhost:7007` if you're accessing via `kubectl port-forward`, just make sure `backend.cors.origin` (derived from the same variable here) matches however you're actually loading the frontend.
- `publish:github` in the scaffolder template needs a real GitHub token either way. For pure local testing without any GitOps setup at all, a direct-apply scaffolder action (calling the Kubernetes API straight from the Backstage backend, no git involved) is a reasonable local-only substitute, not included in this repo since it's explicitly not a GitOps pattern, but straightforward to add as a custom `createTemplateAction` if you want it back for local iteration.
- The Postgres `wait_for_service_account_token` mechanism works on Docker Desktop's Kubernetes as of this writing, but if you hit the hang described in [The Kubernetes plugin](#the-kubernetes-plugin-live-pod-status), the manual `kubectl create token` fallback there applies locally too.
