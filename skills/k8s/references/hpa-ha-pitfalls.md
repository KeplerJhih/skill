# HPA & HA Correctness Pitfalls

Non-obvious failure modes when configuring HorizontalPodAutoscaler and high-availability
spread on production clusters — especially with a service mesh (Istio / ASM / Cloud Service
Mesh) injecting sidecars. Consult before enabling HPA, choosing autoscaling metrics, or
claiming a workload is "HA". All four rules are cloud-neutral.

## 1. With a sidecar, scale on `ContainerResource`, not `Resource`

`type: Resource` computes utilization across the WHOLE pod:
`sum(all container usage) / sum(all container requests)`. When a mesh injects an
`istio-proxy` sidecar (typical request 100m CPU / 128Mi), the sidecar's request lands in the
denominator and dilutes the reading — HPA scales up late.

Concrete: app request 250m + sidecar request 100m = 350m denominator. App genuinely busy at
200m, sidecar idle at ~10m:

- `Resource`: (200+10)/350 = **60%** → below a 65% target → does NOT scale (but the app is
  actually at 80% of its own request)
- `ContainerResource` (app container only): 200/250 = **80%** → scales correctly

Reverse-solve: with `Resource` at target 65%, the app must reach `0.65 × 350 = 227.5m` =
**91% of its own request** before HPA reacts. Scaling arrives far too late.

Fix — target the app container directly:

```yaml
metrics:
- type: ContainerResource      # not Resource
  containerResource:
    name: cpu
    container: myapp           # MUST match the app container name; sidecar excluded
    target:
      type: Utilization
      averageUtilization: 65
```

Requirements / caveats:

- `ContainerResource` is GA since Kubernetes 1.27 — verify `kubectl version` before use.
- `container` must match a container present in every pod, else HPA reports the metric as
  unavailable.
- No sidecar (single-container pod) → `Resource` == `ContainerResource`; the change is
  unnecessary. Only worth it when a sidecar (or any co-container with requests) is present.

Do NOT compensate by lowering the `Resource` threshold instead: the dilution ratio differs
per service (varies with app request size) and the sidecar's own usage drifts with mesh
traffic, so a single global threshold cannot track it. Prefer `ContainerResource`.

## 2. Do not use memory as an HPA scale signal for Go / JVM services

Runtimes that don't promptly return freed heap to the OS (Go with default `MADV_FREE`; JVM
without heap tuning) keep RSS near peak. Memory utilization then only rises, rarely falls →
HPA (which takes the MAX across all metrics) pins replicas high and cannot scale down even
when CPU is idle. This reads to an operator as "scale-down is broken" when the real cause is
the memory metric holding the floor.

Rule: scale on CPU; let memory be an OOM ceiling via `resources.limits`, not an HPA metric.
Setting memory `request == limit` gives predictable, non-overcommitted memory without feeding
a bad scale signal.

If a memory-driven scale is genuinely needed (rare), pair it with `GOMEMLIMIT` / JVM heap
tuning so freed memory actually drops to the OS — otherwise scale-down never fires.

## 3. `minReplicas: 2` + PDB is only HALF of HA — add pod spread

Two replicas and a PodDisruptionBudget protect against *voluntary* disruption (drain, rolling
update). They do NOT stop the scheduler from placing both replicas on the SAME node. One node
failure (or spot reclaim) then takes the whole service to zero, and PDB does nothing against
involuntary loss — so paying for two replicas buys no real node-failure protection.

Always pair the replica count / HPA with `topologySpreadConstraints` so replicas land on
different nodes (and ideally AZs). Verify on the live cluster — do not assume the scheduler
spread them:

```bash
kubectl get pods -l app=myapp -o wide   # confirm replicas are on different nodes
```

## 4. `topologySpread` soft vs hard — soft guarantees node spread, NOT zone spread

`whenUnsatisfiable: ScheduleAnyway` (soft) is a scoring preference, not a rule. In practice
soft achieves cross-node spread reliably but frequently leaves both replicas in the SAME zone
(the scheduler satisfies the node constraint and treats zone as best-effort). Observed on a
real deploy: soft config → 100% cross-node, only ~30% cross-AZ.

| Want | Constraint | Trade-off |
|---|---|---|
| Best-effort spread, never block scheduling | `ScheduleAnyway` (soft) | Node spread reliable; **AZ spread not guaranteed** |
| Guaranteed 1-replica-per-AZ | `DoNotSchedule` (hard) on the zone key | Strong AZ HA; **risks Pending** if a zone has no schedulable capacity |

For a 2-replica stateless service across 2+ AZs with capacity in each, a hard zone constraint
guarantees 1-per-AZ and implies cross-node too. Use hard where AZ resilience matters and
capacity is ample; keep soft where a scheduling stall is worse than imperfect AZ spread.

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: kubernetes.io/hostname          # node spread
  whenUnsatisfiable: ScheduleAnyway            # soft — never blocks
  labelSelector: { matchLabels: { app: myapp } }
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone     # AZ spread
  whenUnsatisfiable: DoNotSchedule             # hard — guarantees 1/AZ (use when capacity ample)
  labelSelector: { matchLabels: { app: myapp } }
```

Decide soft-vs-hard once and apply it consistently across the fleet (all deployments), so HA
behavior is uniform rather than per-service guesswork. A template change alone does not move
already-running pods — a rollout (`kubectl rollout restart`) is required to realize the spread.
