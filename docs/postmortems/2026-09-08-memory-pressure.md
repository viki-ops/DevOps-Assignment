# Postmortem: Memory pressure / OOMKilled stress pod

- **Date:** 2026-09-08
- **Severity:** Sev-3 (demo injection)
- **Evidence:** `docs/evidence/09-failure-injection/2-memory-pressure.log`

## What happened

Two attempts to run an unmanaged memory-stress Pod in `retail-store-dev`:

1. **Blocked by policy.** `polinux/stress` without a tag was denied by the
   Kyverno `disallow-latest-tag` ClusterPolicy. This is the guardrail working
   as designed — an accidental `:latest` never reached a node.
2. **OOMKilled as intended.** A digest-pinned `polinux/stress:1.0.4` Pod was
   admitted with `requests.memory=256Mi` / `limits.memory=512Mi` and asked to
   allocate 1200Mi. The kubelet killed it (`Reason: OOMKilled`, exit 137).

Retail workloads stayed `Running` (10/10) throughout.

## Detection

- Kyverno admission webhook denial on the first attempt (API server response).
- Pod phase `Failed` / container reason `OOMKilled` on the second.
- Kubernetes events: `Killing` / `Started` / `OOMKilled` on the stress Pod.
- Container memory metrics available via Prometheus
  (`container_memory_working_set_bytes`).

## Root cause

An unmanaged Pod requested more memory than its limit. Resource limits
contained the blast radius to that Pod; kubelet reserved memory
(`systemReserved` / `kubeReserved` from the hardened kubelet config) kept the
node agent from being starved.

## Resolution

```bash
kubectl delete pod memory-stress -n retail-store-dev
```

No Git change was required because the Pod was never in GitOps. Had a chart
shipped without memory limits, the fix would have been a values PR (enforced
going forward by `require-resource-limits`).

## Lessons

1. Kyverno caught the untagged image before it consumed capacity — policy is
   part of the detection story, not only runtime metrics.
2. Memory limits convert a node-level outage into a single Pod failure.
3. Unmanaged workloads should be rare; anything long-lived belongs in Git so
   ArgoCD owns its lifecycle.
