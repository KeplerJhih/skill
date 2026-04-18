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
  name: xg-gaming-api-prod
  namespace: xg-gaming-prod
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/instance: api-prod
    app.kubernetes.io/part-of: xg-gaming
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
- **Pod topology** — Use `topologySpreadConstraints` or `podAntiAffinity` to spread across nodes/zones.

---

## Additional Resources

### Reference Files

For detailed templates and checklists, consult:
- **`references/manifest-templates.md`** — Complete YAML templates for all common resource types (Deployment, Service, Ingress, HPA, PDB, CronJob, etc.)
- **`references/security-checklist.md`** — Security audit checklist for K8s manifests (SecurityContext, NetworkPolicy, RBAC, image scanning)
- **`references/resource-sizing.md`** — Resource requests/limits sizing guide by workload type and cloud provider recommendations
- **`references/helm-patterns.md`** — Helm chart patterns, helpers, and values structure conventions
