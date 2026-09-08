# ADR 0005: IRSA token audience is `amazonaws.com`, not `sts.amazonaws.com`

- **Status:** Accepted
- **Date:** 2026-09-07
- **Applies to:** `infra-modules/kops-oidc`, `infra-modules/irsa-role`

## Context

Terraform owns IRSA for this platform (ADR 0001): it creates the OIDC
discovery bucket, the IAM OIDC provider, and every add-on role, and the kOps
spec pins `serviceAccountIssuer` to the same URL.

Almost every IRSA example in circulation is written for EKS, where projected
service account tokens carry the audience `sts.amazonaws.com`. We initially
followed that convention in both places:

- `aws_iam_openid_connect_provider.client_id_list = ["sts.amazonaws.com"]`
- the role trust policies asserted `<issuer>:aud == "sts.amazonaws.com"`

The cluster came up with all seven nodes `Ready`, but every add-on pod stayed
`Pending` and the nodes never lost the
`node.cloudprovider.kubernetes.io/uninitialized` taint. The AWS cloud
controller manager was in `CrashLoopBackOff` with:

```
InvalidIdentityToken: The web identity token provided could not be validated.
```

Two things made this slow to diagnose:

1. **The error names neither the claim nor the value that failed.** It is
   emitted identically for a bad thumbprint, an unreachable issuer, and a
   rejected audience.
2. **`kubectl logs` did not work.** Because the cloud controller manager is
   what assigns node addresses, and it was the component failing, nodes had no
   `InternalIP`, so the API server could not reach any kubelet. Logs had to be
   pulled off the host over SSM Session Manager instead.

Inspecting the DaemonSet showed the actual audience:

```
volumes:
  - name: token-amazonaws-com
    projected:
      sources:
        - serviceAccountToken:
            audience: amazonaws.com
```

and the webhook that serves every other workload agrees:

```
/webhook --token-audience=amazonaws.com ...
```

STS rejects any token whose `aud` claim is absent from the provider's client ID
list, which is exactly what happened.

## Decision

Accept **both** audiences everywhere:

```hcl
token_audiences = ["amazonaws.com", "sts.amazonaws.com"]
```

- `amazonaws.com` is the load-bearing one. kOps projects every add-on token
  with it and runs `pod-identity-webhook` with `--token-audience=amazonaws.com`,
  so it covers both kOps-managed components and our own workloads.
- `sts.amazonaws.com` is kept for SDKs or tooling that request the EKS audience
  explicitly, and to keep these modules reusable against an EKS cluster.

The `kops-oidc` module refuses to build without `amazonaws.com` present:

```hcl
validation {
  condition     = contains(var.token_audiences, "amazonaws.com")
  error_message = "amazonaws.com must be included: kOps addons and the pod-identity-webhook project tokens with that audience, ..."
}
```

Widening the audience list does **not** widen access. Least privilege here is
carried by the `sub` claim, which each role pins to a single
`system:serviceaccount:<namespace>:<name>`. A trust policy that checked only
`aud` would let any ServiceAccount in the cluster assume the role; both claims
are asserted in `infra-modules/irsa-role`.

## A second, independent bug found the same way

The IAM OIDC provider thumbprint was also wrong. The module derived it from the
live TLS chain rather than hard-coding Amazon's CA — correct in principle — but
selected `certificates[length - 1]`.

`hashicorp/tls` returns the chain **root-first**, so that index is the leaf
(`CN=*.s3.eu-north-1.amazonaws.com`): not a CA, and rotated by AWS every few
months. The fix takes `certificates[0]`.

Selecting "the self-signed certificate" instead is tempting and does not work:
`Amazon Root CA 1` is cross-signed by Starfield, so its issuer differs from its
subject. Since correctness now depends on ordering, the module asserts it:

```hcl
precondition {
  condition = (
    length(local.oidc_chain) >= 2 &&
    local.oidc_chain[0].subject == local.oidc_chain[1].issuer
  )
  ...
}
```

## Consequences

- IRSA works for kOps add-ons and for our own workloads without per-workload
  audience configuration.
- Both failure modes now fail loudly: a bad audience is caught by a Terraform
  `validation`, a reordered TLS chain by a `precondition`. Neither can silently
  reach runtime again.
- These modules stay usable against EKS unchanged.

## Verification

The token exchange was confirmed by hand before trusting the controllers:

```console
$ TOK=$(kubectl create token aws-cloud-controller-manager -n kube-system \
        --audience sts.amazonaws.com --duration 3600s)

$ aws sts assume-role-with-web-identity \
    --role-arn arn:aws:iam::125788629837:role/aws-cloud-controller-manager.kube-system.sa.dev.k8s.local \
    --role-session-name probe --web-identity-token "$TOK"
{
  "Assumed": ".../aws-cloud-controller-manager.kube-system.sa.dev.k8s.local/probe"
}
```

The same call against an unrelated role returns `AccessDenied` rather than
`InvalidIdentityToken`, which is the useful distinction: `AccessDenied` proves
the token itself validated and only the `sub` pin rejected it — i.e. the
scoping works.

After the fix, the taint cleared and the cluster converged to 61/61 pods
`Running`. Evidence: `docs/evidence/03-cluster/`.
