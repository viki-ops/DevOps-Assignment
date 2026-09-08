# Teardown (stop AWS spend)

Run **after** the walkthrough / review. Order matters: delete the kOps
cluster first (EC2, ASGs, NLBs, volumes), then the Terraform VPC stack.

## 1) Delete the kOps cluster

```bash
export AWS_REGION=eu-north-1
export KOPS_STATE_STORE=s3://platform-kops-state-eun1-125788629837
export NAME=dev.k8s.local

kops delete cluster --name "${NAME}" --yes
```

Wait until EC2 instances / ASGs for `dev.k8s.local` are gone (often 10–20 min).

## 2) Destroy the Terraform `dev` stack

```bash
cd infra-live/dev
terraform init
terraform destroy -auto-approve
```

Removes VPC, subnets, NAT, private Route53 zone, KMS aliases/roles created by
that stack, etc.

## 3) Optional — bootstrap (state buckets)

Only after no other stacks need the remote backend:

```bash
cd infra-live/_bootstrap
terraform init
terraform destroy -auto-approve
```

This deletes the S3 tfstate / kOps state buckets and DynamoDB lock table.
**Do this last.** Prefer emptying/version-expire first if destroy fails on
non-empty buckets.

## 4) Orphan check

```bash
aws ec2 describe-instances --region eu-north-1 \
  --filters "Name=tag:KubernetesCluster,Values=dev.k8s.local" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output table

aws elbv2 describe-load-balancers --region eu-north-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].[LoadBalancerName,State.Code]' \
  --output table

aws ec2 describe-addresses --region eu-north-1 \
  --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output table
```

Expect no lingering cluster instances, k8s NLBs, or unattached Elastic IPs.
