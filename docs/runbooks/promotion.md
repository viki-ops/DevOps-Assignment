# Promotion: digests move, configs stay

Promotion is a pull request that copies image digests from `gitops/values/apps/dev/`
into `stage/` then `prod/`. Replica counts, nodeSelectors and ingress hosts stay
environment-specific.

## Gate

- **dev** Applications auto-sync.
- **stage** and **prod** Applications have no `automated` syncPolicy: a merge
  leaves them `OutOfSync` until a release-manager clicks Sync (or runs
  `argocd app sync`).

## Prove digest equality

```bash
./scripts/prove-digest-equality.sh
```

Expected: `OK` for all five services with identical `sha256:...` across
dev/stage/prod.

## Simulate a promotion

1. Confirm digests match (script above).
2. `kubectl apply -f gitops/bootstrap/root-stage.yaml`
3. Sync one stage app: `kubectl -n argocd patch application retail-ui-stage --type merge -p '{"operation":{"sync":{"revision":"main"}}}'`
4. Repeat for prod after stage validation.
