# Kubernetes Manifest Templates

Complete YAML templates for common Kubernetes resource types. Adapt to the target project's naming conventions and requirements.

---

## Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {service}-{env}
  namespace: {project}-{env}
  labels:
    app.kubernetes.io/name: {service}
    app.kubernetes.io/instance: {service}-{env}
    app.kubernetes.io/part-of: {project}
    app.kubernetes.io/managed-by: kubectl
spec:
  replicas: 2  # prod >= 2
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app.kubernetes.io/name: {service}
      app.kubernetes.io/instance: {service}-{env}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {service}
        app.kubernetes.io/instance: {service}-{env}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: {service}
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        fsGroup: 65534
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: {service}
      containers:
        - name: {service}
          image: {registry}/{project}/{service}:{tag}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          envFrom:
            - configMapRef:
                name: {service}-config
            - secretRef:
                name: {service}-secret
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

---

## Service

### ClusterIP (internal)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {service}
  namespace: {project}-{env}
  labels:
    app.kubernetes.io/name: {service}
    app.kubernetes.io/instance: {service}-{env}
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
  selector:
    app.kubernetes.io/name: {service}
    app.kubernetes.io/instance: {service}-{env}
```

### NodePort (development/testing)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {service}
  namespace: {project}-{env}
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 30080
  selector:
    app.kubernetes.io/name: {service}
    app.kubernetes.io/instance: {service}-{env}
```

---

## Ingress

### Nginx Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {service}
  namespace: {project}-{env}
  labels:
    app.kubernetes.io/name: {service}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - {domain}
      secretName: {service}-tls
  rules:
    - host: {domain}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {service}
                port:
                  name: http
```

### GKE Ingress (GCE)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {service}
  namespace: {project}-{env}
  annotations:
    kubernetes.io/ingress.class: gce
    kubernetes.io/ingress.global-static-ip-name: {ip-name}
    networking.gke.io/managed-certificates: {cert-name}
spec:
  rules:
    - host: {domain}
      http:
        paths:
          - path: /*
            pathType: ImplementationSpecific
            backend:
              service:
                name: {service}
                port:
                  name: http
```

---

## HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {service}
  namespace: {project}-{env}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {service}-{env}
  minReplicas: 2
  maxReplicas: 10
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

---

## PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {service}
  namespace: {project}-{env}
spec:
  minAvailable: 1  # Or use maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: {service}
      app.kubernetes.io/instance: {service}-{env}
```

---

## ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {service}-config
  namespace: {project}-{env}
data:
  APP_ENV: "{env}"
  APP_PORT: "8080"
  LOG_LEVEL: "info"
  LOG_FORMAT: "json"
```

---

## Secret (ExternalSecret preferred)

### Plain Secret (dev only)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {service}-secret
  namespace: {project}-{env}
type: Opaque
stringData:
  DB_PASSWORD: "changeme"
```

### ExternalSecret (production)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {service}-secret
  namespace: {project}-{env}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store  # or aws-secret-store
    kind: ClusterSecretStore
  target:
    name: {service}-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: {project}-{env}-db-password
```

---

## ServiceAccount + RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {service}
  namespace: {project}-{env}
  annotations:
    # GKE Workload Identity
    iam.gke.io/gcp-service-account: {service}@{gcp-project}.iam.gserviceaccount.com
    # AWS IRSA
    # eks.amazonaws.com/role-arn: arn:aws:iam::{account}:role/{role}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {service}
  namespace: {project}-{env}
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {service}
  namespace: {project}-{env}
subjects:
  - kind: ServiceAccount
    name: {service}
    namespace: {project}-{env}
roleRef:
  kind: Role
  name: {service}
  apiGroup: rbac.authorization.k8s.io
```

---

## NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {service}
  namespace: {project}-{env}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: {service}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {project}-{env}
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to: []  # Allow all egress (restrict as needed)
```

---

## CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {job-name}
  namespace: {project}-{env}
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  startingDeadlineSeconds: 300
  jobTemplate:
    spec:
      backoffLimit: 3
      activeDeadlineSeconds: 3600
      template:
        spec:
          serviceAccountName: {service}
          restartPolicy: OnFailure
          securityContext:
            runAsNonRoot: true
            fsGroup: 65534
          containers:
            - name: {job-name}
              image: {registry}/{project}/{service}:{tag}
              command: ["/app/job"]
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
              securityContext:
                runAsNonRoot: true
                runAsUser: 65534
                readOnlyRootFilesystem: true
                allowPrivilegeEscalation: false
                capabilities:
                  drop: ["ALL"]
```

---

## StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {service}
  namespace: {project}-{env}
spec:
  serviceName: {service}
  replicas: 3
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: {service}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {service}
    spec:
      serviceAccountName: {service}
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        fsGroup: 65534
      containers:
        - name: {service}
          image: {registry}/{project}/{service}:{tag}
          ports:
            - name: http
              containerPort: 8080
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard  # Adjust per cloud provider
        resources:
          requests:
            storage: 10Gi
```

---

## Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {project}-{env}
  labels:
    app.kubernetes.io/part-of: {project}
    environment: {env}
```
