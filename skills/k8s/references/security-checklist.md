# Kubernetes Security Checklist

Comprehensive security audit checklist for Kubernetes manifests.

---

## Pod Security

### SecurityContext (Required)

先確認 image 能否以非 root 執行，再挑 profile — 詳見 SKILL.md Step 4。
把 Profile A 硬套到必須 root 啟動的 image 上，得到的是 `CrashLoopBackOff`，不是安全。

#### Profile A — image 支援非 root（預設，新 workload 一律從這裡開始）

- [ ] `runAsNonRoot: true` — Never run containers as root
- [ ] `runAsUser: 65534` — Use `nobody` user (or specific non-root UID)
- [ ] `readOnlyRootFilesystem: true` — Prevent filesystem writes (use `emptyDir` for temp)
- [ ] `allowPrivilegeEscalation: false` — Prevent privilege escalation
- [ ] `capabilities.drop: ["ALL"]` — Drop all Linux capabilities
- [ ] Only add back specific capabilities if required (e.g., `NET_BIND_SERVICE`)

#### Profile B — image 必須以 root 啟動（官方 nginx / httpd、bind <1024、部分 DB image）

- [ ] 已實測確認非 root 跑不起來（`docker run --rm -u 65534 <image>`），不是憑印象假設
- [ ] `runAsNonRoot` 刻意不設，且 manifest 內有註解寫明原因
- [ ] `allowPrivilegeEscalation: false` — 仍然必須設
- [ ] `readOnlyRootFilesystem: true` + emptyDir 掛所有需寫入路徑（nginx：`/var/cache/nginx`、`/var/run`、`/tmp`）
- [ ] `capabilities.drop: ["ALL"]`，只 add 實際需要的（nginx：`CHOWN`、`SETGID`、`SETUID`、`NET_BIND_SERVICE`）
- [ ] 每個 add 回來的 capability 都能說出用途，不是整組抄
- [ ] Namespace PSA 設 `enforce: baseline`（`restricted` 會擋下此 profile），並保留 `warn: restricted`
- [ ] 有評估過 Profile C（換 unprivileged 變體 / 改 image），Profile B 只作為過渡

### Pod-Level Security

- [ ] `securityContext.fsGroup` set at pod level for shared volume permissions
- [ ] `hostNetwork: false` — No host network access
- [ ] `hostPID: false` — No host PID namespace
- [ ] `hostIPC: false` — No host IPC namespace
- [ ] No `hostPath` volumes unless absolutely necessary (and documented)
- [ ] `automountServiceAccountToken: false` if the pod does not need Kubernetes API access

---

## Image Security

- [ ] Images from trusted registries only (private registry preferred)
- [ ] No `latest` tag — Use immutable tags or SHA256 digests
- [ ] `imagePullPolicy: IfNotPresent` for tagged images
- [ ] Minimal base images (distroless, alpine, scratch)
- [ ] Images scanned for CVEs (Trivy, Snyk, etc.)
- [ ] Image pull secrets configured for private registries

---

## Network Security

### NetworkPolicy

- [ ] Default deny policy exists for the namespace
- [ ] Ingress rules explicitly allow only required sources
- [ ] Egress rules restrict outbound traffic to known destinations
- [ ] Database pods only accept connections from application pods
- [ ] Ingress controller pods explicitly allowed in ingress rules

### Default Deny Template

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: {namespace}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Ingress/Service

- [ ] TLS termination configured (cert-manager or cloud-managed)
- [ ] HTTPS redirect enforced
- [ ] Rate limiting configured where appropriate
- [ ] No services of type `LoadBalancer` unless intentional (prefer Ingress)

---

## RBAC

### ServiceAccount

- [ ] Dedicated ServiceAccount per workload (not `default`)
- [ ] `automountServiceAccountToken: false` on unused service accounts
- [ ] Cloud provider workload identity configured (GKE WI, AWS IRSA, Azure WI)

### Role/RoleBinding

- [ ] Namespace-scoped `Role` preferred over cluster-scoped `ClusterRole`
- [ ] Minimum required verbs (no wildcard `*`)
- [ ] Minimum required resources (no wildcard `*`)
- [ ] No `cluster-admin` binding for application workloads
- [ ] RoleBindings reviewed for over-permissive grants

### RBAC Anti-Patterns

```yaml
# BAD: Over-permissive
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]

# GOOD: Least privilege
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
```

---

## Secrets Management

- [ ] No plaintext secrets in YAML manifests (dev environments excepted)
- [ ] ExternalSecrets or SealedSecrets for production
- [ ] Secret rotation strategy defined
- [ ] Secrets not logged or exposed in environment variable dumps
- [ ] `.env` files excluded from container images

### Recommended Secret Backends

| Cloud | Backend | Tool |
|-------|---------|------|
| GCP | Secret Manager | ExternalSecrets + GCP provider |
| AWS | Secrets Manager / SSM | ExternalSecrets + AWS provider |
| Azure | Key Vault | ExternalSecrets + Azure provider |
| Any | HashiCorp Vault | ExternalSecrets + Vault provider |

---

## Resource Governance

- [ ] `resources.requests` set for all containers
- [ ] `resources.limits` set for all containers
- [ ] `LimitRange` defined per namespace to enforce defaults
- [ ] `ResourceQuota` defined per namespace to cap total usage

### LimitRange Template

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: {namespace}
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "2"
        memory: 2Gi
```

### ResourceQuota Template

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
  namespace: {namespace}
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    services.loadbalancers: "2"
```

---

## Supply Chain Security

- [ ] Pod Security Standards enforced (restricted or baseline)
- [ ] Admission controllers configured (OPA Gatekeeper, Kyverno)
- [ ] Image signature verification (cosign / Sigstore)
- [ ] SBOM generation for container images

### Pod Security Standards (PSS)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {namespace}
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

## Audit Checklist Summary

When reviewing K8s manifests, check each category:

| Category | Priority | Key Check |
|----------|----------|-----------|
| SecurityContext | Critical | `runAsNonRoot`, `readOnlyRootFilesystem`, drop capabilities |
| Images | Critical | No `latest`, scanned for CVEs, trusted registry |
| NetworkPolicy | High | Default deny, explicit ingress/egress rules |
| RBAC | High | Least privilege, no wildcards, dedicated SA |
| Secrets | Critical | No plaintext, external backend for prod |
| Resources | High | Requests and limits set, quotas defined |
| TLS | High | HTTPS enforced, cert-manager configured |
| Supply Chain | Medium | PSS enforced, admission policies, image signing |
