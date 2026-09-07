# ADR 0001: Pin Kubernetes to 1.34.10

**Status:** Accepted
**Date:** 2026-09-07

## Context

The brief requires a "realistic minor version (not latest)" and asks that the choice
be documented.

At the time of building, the landscape was:

- Latest Kubernetes minor released: **1.36** (`1.36.3` current patch)
- Upstream supports the three most recent minors (n-2): **1.34, 1.35, 1.36**
- kOps **1.36.2** is the newest stable kOps; it supports Kubernetes 1.30 through 1.36
- The kOps `stable` channel recommends **1.34.10** for the 1.34 range

## Decision

Pin Kubernetes to **1.34.10**, and pin `kubectl` to the same version.

## Rationale

"Not latest" is easy to satisfy badly. The obvious move is to reach for something
comfortably old such as 1.32 or 1.33, but that fails a more important test: **1.33 and
below are outside the upstream n-2 support window and no longer receive patch or CVE
fixes.** Deliberately shipping an unpatchable control plane is a worse engineering
decision than running the newest release.

1.34.10 threads the needle:

- It is **two minors behind latest**, so it satisfies the letter and the intent of "not
  latest" — the ecosystem has had a full release cycle to catch up, and we are not
  exposed to the churn of a `.0`-era minor.
- It is **still supported upstream**, so security patches keep arriving.
- It is what the **kOps stable channel itself recommends** for the 1.34 range, meaning
  this exact combination is the one kOps regression-tests.
- Every add-on the platform needs — Cluster Autoscaler, AWS Load Balancer Controller,
  cert-manager, ingress-nginx, Cilium, External Secrets — has a GA release supporting
  1.34.

Choosing a `.10` patch rather than `.0` matters too: it is ten patch releases into the
minor's life, so the early-adopter bugs have been shaken out.

## Consequences

- Cluster Autoscaler must be pinned to a matching **1.34.x** image; the autoscaler's
  compatibility policy is per-Kubernetes-minor and mismatches cause subtle scheduling
  bugs rather than loud failures.
- The upgrade runbook ([`docs/runbooks/upgrade.md`](../runbooks/upgrade.md)) targets
  1.34.10 to 1.35.x as the next hop. Skipping minors is not supported by kOps, so the
  path to 1.36 is two rolling upgrades.
- When 1.37 ships, 1.34 leaves the support window and the cluster must move. That is
  tracked as an operational obligation, not a surprise.
