# Helm Chart Patterns

Conventions and patterns for building production-grade Helm charts.

---

## Chart.yaml

```yaml
apiVersion: v2
name: {service-name}
description: A Helm chart for {service-name}
type: application
version: 0.1.0        # Chart version (bump on chart changes)
appVersion: "1.0.0"   # Application version (matches container tag)
```

---

## values.yaml Structure

Organize values by resource type, keeping the top-level flat and predictable:

```yaml
# -- Number of replicas
replicaCount: 2

# -- Container image configuration
image:
  repository: gcr.io/{project}/{service}
  tag: ""  # Defaults to Chart.appVersion
  pullPolicy: IfNotPresent

# -- Image pull secrets
imagePullSecrets: []

# -- Service account configuration
serviceAccount:
  create: true
  name: ""
  annotations: {}

# -- Pod-level security context
podSecurityContext:
  runAsNonRoot: true
  fsGroup: 65534

# -- Container-level security context
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]

# -- Service configuration
service:
  type: ClusterIP
  port: 80
  targetPort: 8080

# -- Ingress configuration
ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts:
    - host: example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

# -- Resource requests and limits
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

# -- HPA configuration
autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

# -- PDB configuration
podDisruptionBudget:
  enabled: false
  minAvailable: 1

# -- Liveness probe
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 10
  periodSeconds: 15

# -- Readiness probe
readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10

# -- Startup probe (for slow-starting apps)
startupProbe:
  httpGet:
    path: /healthz
    port: http
  failureThreshold: 30
  periodSeconds: 5

# -- Node selector
nodeSelector: {}

# -- Tolerations
tolerations: []

# -- Affinity and topology spread
affinity: {}
topologySpreadConstraints: []

# -- ConfigMap data (non-sensitive)
config: {}

# -- Environment variables (in addition to config)
env: []

# -- Extra volume mounts
extraVolumeMounts: []

# -- Extra volumes
extraVolumes: []

# -- NetworkPolicy
networkPolicy:
  enabled: false

# -- Pod annotations
podAnnotations: {}
```

---

## Environment-Specific Values

### values-dev.yaml

```yaml
replicaCount: 1

image:
  tag: "dev-latest"

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi

autoscaling:
  enabled: false

config:
  APP_ENV: "development"
  LOG_LEVEL: "debug"
```

### values-prod.yaml

```yaml
replicaCount: 2

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10

podDisruptionBudget:
  enabled: true
  minAvailable: 1

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls

networkPolicy:
  enabled: true

config:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  LOG_FORMAT: "json"
```

---

## _helpers.tpl

Standard helper templates:

```gotemplate
{{/*
Expand the name of the chart.
*/}}
{{- define "{chart}.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "{chart}.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "{chart}.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "{chart}.labels" -}}
helm.sh/chart: {{ include "{chart}.chart" . }}
{{ include "{chart}.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "{chart}.selectorLabels" -}}
app.kubernetes.io/name: {{ include "{chart}.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "{chart}.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "{chart}.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image with tag fallback to appVersion
*/}}
{{- define "{chart}.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}
```

---

## Helm Commands Quick Reference

```bash
# Create new chart
helm create devops/k8s/charts/{service-name}

# Lint chart
helm lint devops/k8s/charts/{service-name}/

# Render templates locally (dry-run)
helm template {release} devops/k8s/charts/{service-name}/ \
  -f devops/k8s/charts/{service-name}/values-dev.yaml

# Diff before upgrade (requires helm-diff plugin)
helm diff upgrade {release} devops/k8s/charts/{service-name}/ \
  -f values-prod.yaml --namespace {namespace}

# Install / Upgrade
helm upgrade --install {release} devops/k8s/charts/{service-name}/ \
  -f values-{env}.yaml \
  --namespace {namespace} \
  --create-namespace \
  --wait --timeout 5m

# Rollback
helm rollback {release} {revision} --namespace {namespace}

# History
helm history {release} --namespace {namespace}

# Uninstall
helm uninstall {release} --namespace {namespace}
```

---

## Chart Testing

```bash
# Install chart-testing tool
# brew install chart-testing

# Run chart-testing lint
ct lint --charts devops/k8s/charts/{service-name}/

# Run chart-testing install (requires kind cluster)
ct install --charts devops/k8s/charts/{service-name}/
```

---

## Common Patterns

### Conditional Resources

```gotemplate
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
...
{{- end }}
```

### Loop Over Environment Variables

```gotemplate
env:
  {{- range $key, $value := .Values.config }}
  - name: {{ $key }}
    value: {{ $value | quote }}
  {{- end }}
  {{- with .Values.env }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
```

### Optional ConfigMap

```gotemplate
{{- if .Values.config }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "{chart}.fullname" . }}-config
  labels:
    {{- include "{chart}.labels" . | nindent 4 }}
data:
  {{- range $key, $value := .Values.config }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
{{- end }}
```

---

## Common Pitfalls

### 1. Image 路徑：支援短名稱與完整路徑

當 chart 使用 `global.image.registry` 統一管理 registry 時，模板應同時支援兩種 image 寫法：

| 寫法 | values 範例 | 渲染結果 |
|------|------------|---------|
| 短名稱 | `image: my-service` | `{registry}/my-service:{tag}` |
| 完整路徑 | `image: gcr.io/other/svc` | `gcr.io/other/svc:{tag}` |

**模板實作：** 用 `contains "/"` 判斷是否為完整路徑：

```gotemplate
{{- $imageName := $app.image | default $appName }}
{{- $imageTag := $app.tag | default $globalTag }}
{{- if contains "/" $imageName }}
image: "{{ $imageName }}:{{ $imageTag }}"
{{- else }}
image: "{{ $registry }}/{{ $imageName }}:{{ $imageTag }}"
{{- end }}
```

**常見錯誤：** values 寫了完整路徑但模板無條件拼接 registry，導致路徑重複：
```
# ❌ asia-southeast1-docker.pkg.dev/proj/repo/asia-southeast1-docker.pkg.dev/proj/repo/svc:tag
```

**排查方式：**
```bash
helm template release charts/my-chart/ -f values.yaml | grep "image:"
```

### 2. imagePullPolicy：全局預設 + Per-app 覆蓋

在 `defaults` 定義全局預設，per-app 可選覆蓋，模板用一行解決：

```gotemplate
{{- $imagePullPolicy := $app.imagePullPolicy | default $.Values.defaults.imagePullPolicy }}
imagePullPolicy: {{ $imagePullPolicy }}
```

```yaml
# values.yaml
defaults:
  imagePullPolicy: IfNotPresent    # 全局預設

apps:
  my-service:
    image: my-service
    # imagePullPolicy: Always       # 需要時才覆蓋
```

**原則：** tagged images 用 `IfNotPresent`，mutable tags 才用 `Always`，永遠不用 `latest`。

### 3. Nil-safe 存取 global values

當模板引用 `global.image.registry` 等巢狀欄位時，**必須**加 nil-safe 檢查。因為 `global.image` 可能被註解掉、被其他 values 檔覆蓋為空、或根本未定義。

**錯誤寫法：** 直接存取，`global.image` 為 nil 時會 panic：

```gotemplate
# ❌ nil pointer evaluating interface {}.registry
{{- $registry := $.Values.global.image.registry }}
```

**正確寫法：** 先檢查父層是否存在，再存取子欄位：

```gotemplate
# ✅ nil-safe
{{- $registry := "" }}
{{- if and $.Values.global $.Values.global.image }}
{{- $registry = $.Values.global.image.registry | default "" }}
{{- end }}
{{- $globalTag := "" }}
{{- if and $.Values.global $.Values.global.image }}
{{- $globalTag = $.Values.global.image.tag | default "" }}
{{- end }}
```

**適用場景：** 所有巢狀超過一層的 values 存取（`global.image.*`、`app.healthCheck.*`、`app.hpa.*` 等），只要該父層可能為空就需要防護。

### 4. GKE 控制器管理的 Annotation 不可由 Helm 重複定義

在 GKE 環境中，部分 annotation 由 GKE 控制器（如 Gateway Controller、Ingress Controller）自動管理。如果 Helm chart 也定義了相同的 annotation，Server-Side Apply 會偵測到 field manager 衝突並拒絕部署。

**常見衝突 annotation：**

| Annotation | 管理者 |
|------------|--------|
| `cloud.google.com/neg` | GKE Gateway Controller / NEG Controller |
| `cloud.google.com/backend-config` | GKE Ingress Controller |
| `networking.gke.io/managed-certificates` | GKE Certificate Controller |

**錯誤寫法：** Helm chart 中寫死 GKE 控制器管理的 annotation：

```yaml
# ❌ 與 GKE Gateway Controller 衝突
metadata:
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
```

**錯誤訊息特徵：**
```
Apply failed with 1 conflict: conflict with "Google GKE Gateway Controller" using v1: .metadata.annotations.cloud.google.com/neg
```

**正確做法：** 不在 Helm chart 中定義這些 annotation，讓 GKE 控制器自行管理：

```yaml
# ✅ 不寫 GKE 控制器管理的 annotation
metadata:
  name: {{ $appName }}
  namespace: {{ $.Values.namespace }}
spec:
  ...
```

**若確實需要自訂 NEG 設定：** 使用 `BackendConfig` CRD 而非直接在 Service annotation 上操作。

**排查方式：**
```bash
# 檢查現有 field manager
kubectl get svc {service-name} -n {namespace} --show-managed-fields -o json | jq '.metadata.managedFields[] | {manager, fieldsV1}'
```

---

### 5. Values 註解必須準確描述 image 格式

Values 檔案中的 image 欄位註解必須明確說明支援的格式，避免維護者誤填：

```yaml
# image: 短名稱 (e.g. game-server-go) → 自動拼接 {global.image.registry}/{image}:{tag}
#        完整路徑 (含 "/", e.g. gcr.io/other-project/svc) → 直接使用 {image}:{tag}
```
