# ADR 0004: What kOps manages versus what ArgoCD manages

- **Status:** Accepted
- **Date:** 2026-09-07
- **Applies to:** `cluster-ops/`, `gitops/`

## Context

The brief asks for GitOps to be the delivery mechanism, and the instinct is to
put everything in Git. But some components have to exist before the thing that
reconciles Git exists. Drawing that line badly produces either a cluster that
cannot bootstrap, or two systems that both believe they own the same object and
fight over it.

## Decision

kOps manages only what is required for the cluster to be a functioning
Kubernetes cluster that ArgoCD can then run on. Everything else is an ArgoCD
Application.

**kOps-managed** (declared in the cluster spec, `cluster-ops/`):

- **Cilium** — the CNI. Nodes are `NotReady` without it, so nothing can be
  scheduled, including ArgoCD.
- **CoreDNS** — cluster DNS.
- **AWS cloud controller manager** — assigns node addresses and zone labels and
  clears the `uninitialized` taint. Nothing schedules until it runs.
- **EBS CSI driver** — the in-tree provisioner is gone in modern Kubernetes;
  without CSI every PVC stays `Pending`, including Prometheus's.
- **metrics-server** — required by HPA, which Part 3 depends on.
- **pod-identity-webhook** — injects `AWS_ROLE_ARN` and the projected token
  volume. Without it the `eks.amazonaws.com/role-arn` annotation does nothing
  and every IRSA workload silently falls back to the node role. ArgoCD itself
  uses IRSA, so this must precede it.
- **cert-manager** — a special case, discussed below.

**ArgoCD-managed** (`gitops/`):

ingress-nginx, external-dns, cluster-autoscaler, AWS Load Balancer Controller,
External Secrets Operator, Kyverno, kube-prometheus-stack, ClusterIssuers and
Certificates, and all application workloads.

## Why cert-manager is kOps-managed

cert-manager is the one component that breaks the rule, and it is worth being
explicit about why rather than letting it look like an oversight.

`podIdentityWebhook` is a mutating admission webhook, so it needs a serving
certificate before it can accept traffic, and kOps provisions that through
cert-manager during cluster creation. Since the webhook must exist before
ArgoCD (ArgoCD uses IRSA), cert-manager must exist before that again.

cert-manager also supports only one installation per cluster — its CRDs are
cluster-scoped and a second copy conflicts. So it cannot be "bootstrapped by
kOps and then adopted by ArgoCD" without the two fighting over the same CRDs.

The split we take instead: **kOps owns the cert-manager installation, GitOps
owns everything cert-manager does.** `ClusterIssuer` and `Certificate` objects
live in `gitops/` like any other manifest. That keeps the interesting,
frequently-changed configuration in Git while leaving the bootstrap-critical
controller where it has to be.

## Consequences

- The cluster reaches a working state from `cluster-create.yml` alone, with no
  chicken-and-egg between ArgoCD and the things ArgoCD needs.
- There is exactly one owner per object, so no sync loops between kOps and
  ArgoCD.
- Changing a kOps-managed add-on requires an Ansible run and possibly a rolling
  update, rather than a pull request. This is the real cost of the decision and
  the reason the list is kept as short as it is.
- The boundary is visible in the cluster spec: the kOps-managed set is a short,
  commented block that points here.
