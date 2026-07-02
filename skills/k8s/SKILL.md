---
name: k8s
description: >-
  This skill should be used when the user asks to "create K8s manifests", "write Deployment YAML",
  "set up Kubernetes Service", "create Ingress", "write Helm chart", "create Kustomize overlay",
  "deploy to Kubernetes", "add HPA", "create NetworkPolicy", "set up RBAC", "review K8s security",
  "create ConfigMap", "create Secret", "add health probes", "set resource limits",
  "create CronJob", "write PodDisruptionBudget", or mentions Kubernetes, K8s, kubectl, Helm,
  Kustomize, GKE, EKS, AKS, or container orchestration.
  Also triggered when working with Helm charts: "helm install", "helm upgrade", "helm template",
  "helm lint", "helm values", "fix helm", "helm failed", "helm debug", editing values*.yaml
  or Chart.yaml files, or troubleshooting Helm deployment failures. When Helm is involved,
  always consult references/helm-patterns.md (especially Common Pitfalls section) before making changes.
  Also triggered when connecting to or switching clusters: "connect to a cluster", "switch context",
  "switch kubeconfig", "set KUBECONFIG", "kubectl config use-context", "連線叢集", "切換叢集",
  "kubeconfig 管理" — in which case follow Step 0 (Cluster Connection / Kubeconfig) and use the
  `switch` (kubeswitch) tool before running any live-cluster command.
version: 0.1.0
---

# Kubernetes Skill

Generate, manage, and review Kubernetes manifests, Helm charts, and Kustomize overlays for production-grade deployments.

## Core Principles

- **Declarative First** — All resources defined as YAML manifests under version control. No imperative `kubectl run` in production.
- **Security by Default** — Non-root containers, read-only root filesystem, drop all capabilities, enforce NetworkPolicy.
- **Resource Governance** — Every container must declare `requests` and `limits`. No unbounded workloads.
- **High Availability** — Production workloads require `replicas >= 2`, PodDisruptionBudget, and pod anti-affinity.
- **Observability** — All containers must define `livenessProbe`, `readinessProbe`, and optionally `startupProbe`.
- **Namespace Isolation** — Each environment (dev/staging/prod) operates in its own namespace. No resources in `default`.
- **Immutable Tags** — Never use `latest` or mutable tags. Pin image digests or semantic version tags.
- **Least Privilege RBAC** — Service accounts get only required verbs on specific resources. No cluster-admin for workloads.

---

## Workflow

### Step 0: Cluster Connection / Kubeconfig (MANDATORY before any live-cluster command)

Any command that touches a live cluster — `kubectl`, `helm install/upgrade`, `kubectl apply` — requires an explicit, confirmed cluster selection first. Never rely on the implicit merged `~/.kube/config` default context, and never assume which cluster is active.

**統一存放位置** — Store every kubeconfig under `$HOME/.kube/configs/`, one file per cluster (many clusters → many files, hence the plural `configs/`). Each file must end in `.yaml` so the `switch` store matches it (`kubeconfigName: "*.yaml"`).

**命名規則** — `<集群帳號>-<gke集群名稱>.yaml`:
- **集群帳號** — cloud account / GCP project / environment identity.
- **gke集群名稱** — the real cluster name from `gcloud container clusters list`.

實際範例（`$HOME/.kube/configs/`）：

```
gke-january01-487003-asia-southeast1-gke-gaming.yaml   # GKE: <gcp-project>-<region>-<cluster>
aliyun-aquawin.yaml                                    # 其他雲沿用 <帳號>-<叢集>.yaml
asm-aquawin-uat.yaml
onprem-105.yaml
```

**連線統一透過 `switch`（kubeswitch / switcher）** — Never `export KUBECONFIG` by hand. The `switch` tool is already installed (`~/.zshrc` has `source <(switcher init zsh)`); its store is `~/.kube/switch-config.yaml` (`kind: filesystem`, paths → `~/.kube/configs`):

```bash
switch            # fuzzy 選單，列出 configs/ 內所有叢集 context
switch gaming     # 以關鍵字過濾
# 選定後印出 "switched to context <name>"，並把 KUBECONFIG 指向該檔
```

**連線後、執行 live 指令前**（尤其 `apply` / `helm upgrade` 等寫入類），打印目標再確認：

```bash
kubectl config current-context
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
kubectl config view --minify -o jsonpath='{..namespace}{"\n"}'
```

Confirm context / server / namespace before proceeding. This gate is mandatory for every live-cluster command (read or write).

新增叢集：把 kubeconfig 放進 `$HOME/.kube/configs/`，依命名規則存成 `<集群帳號>-<gke集群名稱>.yaml`，`switch` 會自動偵測，無需改設定。

### Step 1: Understand Requirements

Before writing any manifests, clarify:

1. **Target cluster** — GKE, EKS, AKS, or self-managed. This affects Ingress class, StorageClass, and annotations.
2. **Workload type** — Deployment, StatefulSet, DaemonSet, Job, or CronJob.
3. **Networking** — Internal-only or external-facing. Need Ingress, LoadBalancer, or ClusterIP.
4. **Storage** — Ephemeral, PVC, or external (Cloud SQL, S3, etc.).
5. **Existing manifests** — Scan for existing K8s files in `devops/k8s/`.

```bash
# Scan for existing K8s manifests
find devops/k8s/ -name "*.yaml" -o -name "*.yml" 2>/dev/null
# Check for Helm charts
find . -name "Chart.yaml" 2>/dev/null
# Check for Kustomize
find . -name "kustomization.yaml" 2>/dev/null
```

Present findings and confirm scope with the user before proceeding.

### Step 2: Choose Manifest Strategy

| Scenario | Strategy | When to Use |
|----------|----------|-------------|
| Single service, few envs | Plain YAML + Kustomize | Simple projects, minimal templating needed |
| Multiple services, shared patterns | Helm chart | Reusable across services, complex templating |
| Existing Helm + env overrides | Kustomize + Helm | Post-render patching for environment differences |

### Step 3: Generate Manifests

For each workload, generate the required resources in this order:

1. **Namespace** — `namespace.yaml`
2. **ConfigMap / Secret** — `configmap.yaml`, `secret.yaml` (external-secrets if available)
3. **ServiceAccount + RBAC** — `serviceaccount.yaml`, `role.yaml`, `rolebinding.yaml`
4. **Workload** — `deployment.yaml`, `statefulset.yaml`, etc.
5. **Service** — `service.yaml`
6. **Ingress / Gateway** — `ingress.yaml`
7. **Autoscaling** — `hpa.yaml`
8. **Disruption Budget** — `pdb.yaml`
9. **NetworkPolicy** — `networkpolicy.yaml`

Follow naming convention: `{resource-type}.yaml` within a service directory.

Consult `references/manifest-templates.md` for complete resource templates.

### Step 4: Apply Security Hardening

Every workload must include a SecurityContext. Consult `references/security-checklist.md` for the full checklist.

Minimum required SecurityContext:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Step 5: Validate

```bash
# Lint manifests
kubectl apply --dry-run=client -f devops/k8s/

# Validate with kubeconform (if available)
kubeconform -strict -summary devops/k8s/

# Helm lint (if using Helm)
helm lint devops/k8s/charts/{chart-name}/

# Template render check
helm template {release} devops/k8s/charts/{chart-name}/ -f values-dev.yaml
```

Present validation results. **Never run `kubectl apply` without explicit user approval.**

### Step 6: Apply

Only after user confirmation:

```bash
kubectl apply -f devops/k8s/{env}/ --namespace={namespace}
# Or with Helm
helm upgrade --install {release} devops/k8s/charts/{chart-name}/ \
  -f values-{env}.yaml --namespace={namespace}
```

---

## Directory Structure

### Plain YAML + Kustomize

```
devops/k8s/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   └── networkpolicy.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── patches/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patches/
    └── prod/
        ├── kustomization.yaml
        └── patches/
```

### Helm Chart

```
devops/k8s/
└── charts/
    └── {service-name}/
        ├── Chart.yaml
        ├── values.yaml
        ├── values-dev.yaml
        ├── values-staging.yaml
        ├── values-prod.yaml
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml
            ├── service.yaml
            ├── ingress.yaml
            ├── hpa.yaml
            ├── pdb.yaml
            ├── configmap.yaml
            ├── serviceaccount.yaml
            └── networkpolicy.yaml
```

---

## Resource Naming Convention

All resources follow: `{project}-{service}-{env}`

```yaml
metadata:
  name: acme-shop-api-prod
  namespace: acme-shop-prod
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/instance: api-prod
    app.kubernetes.io/part-of: acme-shop
    app.kubernetes.io/managed-by: helm  # or kubectl
```

---

## Best Practices

- **Tag everything** — All resources must include standard Kubernetes labels (`app.kubernetes.io/*`).
- **Resource limits are mandatory** — Set `requests` to typical usage, `limits` to burst ceiling. Consult `references/resource-sizing.md`.
- **Probes for all containers** — `readinessProbe` gates traffic; `livenessProbe` restarts unhealthy pods; `startupProbe` for slow-starting apps.
- **No secrets in manifests** — Use ExternalSecrets, SealedSecrets, or cloud-native secret managers. Plain Secret manifests must reference external sources.
- **Image pull policy** — Use `IfNotPresent` for tagged images, `Always` only for mutable tags (which should be avoided).
- **Graceful shutdown** — Set `terminationGracePeriodSeconds` to match application drain time. Handle `SIGTERM`.
- **Pod topology & HA** — Use `topologySpreadConstraints` to spread replicas across nodes/zones. `minReplicas: 2` + PDB alone is only *half* HA — replicas can still co-locate on one node, so a single node failure takes the service to zero. Soft (`ScheduleAnyway`) reliably spreads across nodes but NOT across AZs; use hard (`DoNotSchedule`) on the zone key for guaranteed AZ HA. See `references/hpa-ha-pitfalls.md`.
- **HPA correctness (mesh-aware)** — With an injected sidecar, scale on `type: ContainerResource` targeting the app container, not `Resource` (whole-pod utilization is diluted by the sidecar's request → HPA scales up late). Do not use memory as a scale signal for Go/JVM services (heap is not returned to the OS → replicas pin high and never scale down); keep memory as an OOM `limit` instead. See `references/hpa-ha-pitfalls.md`.
- **Confirm the target cluster first** — Never touch a live cluster without selecting it via `switch` and confirming the printed context/server/namespace (Step 0). No ad-hoc `export KUBECONFIG`.

---

## Additional Resources

### Reference Files

For detailed templates and checklists, consult:
- **`references/manifest-templates.md`** — Complete YAML templates for all common resource types (Deployment, Service, Ingress, HPA, PDB, CronJob, etc.)
- **`references/security-checklist.md`** — Security audit checklist for K8s manifests (SecurityContext, NetworkPolicy, RBAC, image scanning)
- **`references/resource-sizing.md`** — Resource requests/limits sizing guide by workload type and cloud provider recommendations
- **`references/helm-patterns.md`** — Helm chart patterns, helpers, and values structure conventions
- **`references/hpa-ha-pitfalls.md`** — HPA correctness (`ContainerResource` vs `Resource` with sidecars, memory-metric caveat) and HA spread (`topologySpreadConstraints` soft vs hard, node vs AZ); read before enabling HPA or claiming a workload is HA
