# Postmortem: Ingress host drift (self-healed)

- **Date:** 2026-09-08
- **Severity:** Sev-3 (demo injection)
- **Duration to heal:** ~10 seconds
- **Evidence:** `docs/evidence/09-failure-injection/1-ingress-drift.log`

## What happened

An operator patched the retail UI Ingress out-of-band:

```text
store.corp.example.internal  →  drifted.example.invalid
```

ArgoCD marked the Application OutOfSync (briefly) and `selfHeal: true` on
`retail-ui` restored the host from Git.

## Detection

- ArgoCD Application sync status flipped from Synced.
- Ingress hostname no longer matched `gitops/values/apps/dev/ui.yaml`.

## Root cause

Live cluster state was mutated outside Git. That is exactly the class of
change GitOps is meant to reject.

## Resolution

No manual fix required. ArgoCD reconciled the Ingress back to
`store.corp.example.internal` within one reconciliation cycle (~10s observed).

## Lessons

1. Self-heal makes kubectl-edit accidents recoverable without a war room.
2. Changes that should stick must land as a pull request to
   `gitops/values/apps/...`, not a live patch.
3. For deliberate emergency overrides, suspend the Application first
   (`argocd app set retail-ui --sync-policy none`) so heal does not fight the
   break-glass change.
