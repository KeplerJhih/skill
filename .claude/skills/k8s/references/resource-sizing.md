# Resource Sizing Guide

Guidelines for setting Kubernetes resource `requests` and `limits` by workload type.

---

## General Principles

1. **Requests** = typical steady-state usage. The scheduler uses this for placement.
2. **Limits** = maximum burst ceiling. Exceeding memory limits triggers OOMKill; exceeding CPU limits triggers throttling.
3. **CPU ratio** — Start with `limits = 2-5x requests`. Adjust based on profiling.
4. **Memory ratio** — Start with `limits = 1.5-2x requests`. Memory is incompressible; be conservative.
5. **Measure first** — Use Prometheus + Grafana or cloud monitoring to observe actual usage before tuning.

---

## Sizing by Workload Type

### Go API Server

```yaml
# Light API (CRUD, simple logic)
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Medium API (business logic, external calls)
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Heavy API (computation, large payloads)
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 1Gi
```

### Python API Server (Flask/FastAPI + Gunicorn)

```yaml
# Light API
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Medium API
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 1Gi

# Heavy API (ML inference, data processing)
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 2Gi
```

### Node.js API Server

```yaml
# Light API
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Medium API
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 1Gi
```

### Frontend (Nginx serving static files)

```yaml
resources:
  requests:
    cpu: 10m
    memory: 16Mi
  limits:
    cpu: 100m
    memory: 64Mi
```

### Background Worker / Job

```yaml
# Light worker (queue consumer)
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Heavy worker (data processing, ETL)
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 2Gi
```

### CronJob

```yaml
# Light cron (cleanup, notifications)
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Heavy cron (reports, data migration)
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 4Gi
```

### Database Sidecar (Cloud SQL Proxy, PgBouncer)

```yaml
# Cloud SQL Auth Proxy
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

---

## HPA Sizing

| Workload | Min Replicas | Max Replicas | CPU Target | Memory Target |
|----------|-------------|-------------|------------|---------------|
| API (dev) | 1 | 3 | 70% | - |
| API (prod) | 2 | 10 | 70% | 80% |
| Worker (prod) | 2 | 20 | 60% | 70% |
| Frontend (prod) | 2 | 5 | 50% | - |

---

## Cloud Provider Recommendations

### GKE

- Use **Autopilot** for automatic resource right-sizing
- Enable **Vertical Pod Autoscaler (VPA)** in recommendation mode first
- Node pools: `e2-standard-4` (4 vCPU, 16 GB) for general workloads
- Spot/preemptible VMs for non-critical workloads (batch jobs, dev)

### EKS

- Use **Karpenter** for node auto-provisioning
- Enable **right-sizing recommendations** in AWS Cost Explorer
- Graviton instances (`m7g`, `c7g`) for cost-efficient ARM workloads
- Spot instances for fault-tolerant workloads

### AKS

- Enable **AKS cost analysis** for visibility
- Use **KEDA** for event-driven autoscaling
- Standard_D4s_v5 for general workloads

---

## Right-Sizing Workflow

1. **Deploy with initial estimates** from the tables above
2. **Observe for 7 days** using Prometheus metrics:
   - `container_cpu_usage_seconds_total`
   - `container_memory_working_set_bytes`
3. **Set requests** to P95 of observed usage
4. **Set limits** to peak observed + 30% headroom
5. **Enable VPA** in recommendation mode to get ongoing suggestions
6. **Review monthly** and adjust

### Prometheus Queries

```promql
# CPU P95 over 7 days
quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{container="{service}"}[5m])[7d:])

# Memory P95 over 7 days
quantile_over_time(0.95, container_memory_working_set_bytes{container="{service}"}[7d:])

# CPU request vs actual
sum(rate(container_cpu_usage_seconds_total{container="{service}"}[5m]))
/
sum(kube_pod_container_resource_requests{container="{service}", resource="cpu"})
```
