# borsboomh-terraform

Multi-environment EKS deployment on AWS using Terraform. Provisions networking and an EKS cluster (control plane + managed node group) across three environments: dev, qa, and prd.

---

## Project Structure

```
borsboomh-terraform/
├── bootstrap/                   # Run once: creates the S3 remote state bucket
├── modules/
│   ├── vpc/                     # VPC networking (data sources + EKS subnet tags)
│   └── eks/                     # IAM roles, EKS control plane, access entry, node group
├── environments/
│   ├── dev/                     # backend.tfvars + vars.tfvars for dev
│   ├── qa/                      # backend.tfvars + vars.tfvars for qa
│   └── prd/                     # backend.tfvars + vars.tfvars for prd
├── Results/                     # kubectl and terraform output evidence
├── main.tf                      # Root module — calls vpc and eks modules
└── providers.tf                 # AWS provider + partial S3 backend config
```

The project uses a **single root module** at the repository root. The `environments/<env>/` directories are not separate Terraform root modules — they each contain two configuration files:

- `backend.tfvars` — environment-specific backend values (S3 bucket, key, region)
- `vars.tfvars` — environment-specific variable values (instance type, node counts)

Running `terraform init -backend-config=environments/dev/backend.tfvars` points Terraform at a separate state key in S3 for that environment. The separate state keys make it impossible for an apply in one environment to affect another environment's state.

---

## Prerequisites

1. Terraform >= 1.3 installed
2. AWS credentials configured (`aws configure` or environment variables)
3. kubectl installed
4. Verify all three: `terraform version`, `kubectl version --client`, `aws sts get-caller-identity`

---

## Step 1 — Run Bootstrap (once only)

The S3 bucket for remote state must exist before any environment can initialise. This is the classic Terraform bootstrapping problem: remote state cannot store the infrastructure that provides remote state.

The `bootstrap/` directory solves this with a local-state configuration that runs once:

```bash
cd bootstrap
terraform init
terraform plan
terraform apply
```

Confirm the output shows `state_bucket_name = "borsboomh-tfstate"`.

The `bootstrap/terraform.tfstate` file is created locally. Do not commit it and do not delete it — it is the only Terraform record of the bootstrap infrastructure.

---

## Step 2 — Deploy an Environment

All environments are deployed from the **repository root** (`borsboomh-terraform/`). Use the appropriate `backend.tfvars` and `vars.tfvars` for the target environment.

### Deploy dev

```bash
# Run from borsboomh-terraform/
terraform init -backend-config=environments/dev/backend.tfvars
terraform plan -var-file=environments/dev/vars.tfvars
terraform apply -var-file=environments/dev/vars.tfvars
```

### Deploy qa

```bash
terraform init -reconfigure -backend-config=environments/qa/backend.tfvars
terraform plan -var-file=environments/qa/vars.tfvars
terraform apply -var-file=environments/qa/vars.tfvars
```

### Deploy prd

```bash
terraform init -reconfigure -backend-config=environments/prd/backend.tfvars
terraform plan -var-file=environments/prd/vars.tfvars
terraform apply -var-file=environments/prd/vars.tfvars
```

> `-reconfigure` is required when switching the backend between environments on the same machine.

After a successful apply, update your kubeconfig and verify the cluster is reachable:

```bash
aws eks update-kubeconfig --name borsboomh-eks-dev --region af-south-1
kubectl get nodes -o wide
kubectl get pods -A
```

---

## Remote State Strategy

All three environments share a single S3 bucket (`borsboomh-tfstate`) but store state in separate objects:

| Environment | State key |
|---|---|
| dev | `dev/terraform.tfstate`  |
| qa  | `qa/terraform.tfstate`   |
| prd | `prod/terraform.tfstate` |

State locking uses S3 native locking (`use_lockfile = true`). Terraform writes a `.tflock` object alongside each state file. No DynamoDB table is required. S3 bucket versioning and AES256 server-side encryption are enabled to protect state contents.

---

## Environment Configuration

| Environment | Instance type | Desired nodes | Min | Max |
|---|---|---|---|---|
| dev | t3.small  | 1 | 1 | 2 |
| qa  | t3.medium | 2 | 1 | 3 |
| prd | t3.large  | 3 | 2 | 5 |

---

## GitHub Actions CI (Bonus)

A CI workflow (`.github/workflows/terraform.yml`) runs `terraform init`, `terraform validate`, and `terraform plan` for all three environments in parallel on every push and pull request to `main`.

The workflow requires two GitHub Actions secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Plan only — apply is intentionally manual to prevent automated changes to production.

---

## Design Decisions and Trade-offs

**Single root module with var-file environment overrides:** All three environments share one root module and one set of reusable modules. Switching environments requires reinitialising with a different `backend.tfvars` and passing a different `vars.tfvars`. This avoids code duplication at the cost of requiring `-reconfigure` when switching environments on the same machine. An alternative is a separate root module per environment (one `main.tf` per environment calling the shared modules), which allows all three to coexist simultaneously without reinitialisation.

**VPC: default VPC used on shared account:** The full VPC creation code (VPC, subnets, Internet Gateway, route tables, subnet tagging) is defined in `modules/vpc/main.tf` as commented resource blocks. The shared training account reached the 5-VPC regional limit before this project was deployed, so the module was adapted to reference the existing default VPC via data sources and apply the EKS subnet tags to its subnets using `aws_ec2_tag`. On a fresh AWS account, uncomment the resource blocks and update the outputs to reference them.

**EKS API authentication mode:** The EKS cluster uses `authentication_mode = "API"` and access entries instead of the legacy `aws-auth` ConfigMap. This grants the Terraform caller cluster-admin rights automatically after apply, without requiring a separate `kubectl apply` step.

**S3 native state locking:** State locking uses S3's built-in locking (`use_lockfile = true`) rather than a DynamoDB table. This removes a bootstrapping dependency — the S3 bucket alone is sufficient; no second resource needs to exist before state can be used.

**Node sizing by environment:** dev uses t3.small (1 node) to minimise cost. qa uses t3.medium (2 nodes) for basic multi-node testing. prd uses t3.large (3 nodes minimum) for workload headroom and rolling update capacity.

---

## Deployment Evidence (dev)

The dev environment was successfully applied on 2026-07-24. Evidence is saved in `Results/`:

| File | Contents |
|---|---|
| `dev-terraform-outputs.txt` | Terraform outputs and resource summary |
| `dev-kubectl-get-nodes.txt` | `kubectl get nodes -o wide` — 1 node, Ready |
| `dev-kubectl-get-pods.txt`  | `kubectl get pods -A` — 4 system pods Running |
| `dev-cluster-info.txt`      | Cluster API endpoint and client/server versions |

```
kubectl get nodes -o wide output:
NAME                                           STATUS   ROLES    AGE   VERSION
ip-172-31-44-134.af-south-1.compute.internal   Ready    <none>   82s   v1.32.13-eks-8f14419
```

---

## Known Limitations

- **VPC creation code is commented out.** The shared training account reached the 5-VPC regional limit. On a fresh account, uncomment the resource blocks in `modules/vpc/main.tf` and revert `modules/vpc/outputs.tf` to reference them.
- **Single root module pattern requires `-reconfigure` between environments.** An alternative design with per-environment root modules avoids this but duplicates provider and backend boilerplate.
- **`bootstrap/terraform.tfstate` is stored locally.** If it is lost, the S3 bucket would need to be manually imported with `terraform import`.
- **EKS version is pinned to `1.32`** via the module default. Check supported versions before applying: `aws eks describe-addon-versions --region af-south-1`.
- **No NAT Gateway.** Worker nodes have public IPs. Acceptable for training; not recommended for production workloads with private subnets.

---

## Teardown

To destroy a single environment:

```bash
# Run from borsboomh-terraform/
terraform init -reconfigure -backend-config=environments/dev/backend.tfvars
terraform destroy -var-file=environments/dev/vars.tfvars
```

The state bucket is not destroyed by environment teardown. To remove the bootstrap infrastructure after all environments are destroyed:

```bash
# Empty the bucket first — Terraform cannot delete a non-empty versioned bucket
aws s3 rm s3://borsboomh-tfstate --recursive
cd bootstrap
terraform destroy
```
