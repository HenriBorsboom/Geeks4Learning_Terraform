# borsboomh-terraform

Multi-environment EKS deployment on AWS using Terraform. Provisions a VPC and EKS cluster (control plane + access entry) across three environments: dev, qa, and prd.

---

## Project Structure

```
borsboomh-terraform/
├── bootstrap/                   # Run once: creates the S3 remote state bucket
├── modules/
│   ├── vpc/                     # VPC and subnets across 3 AZs
│   └── eks/                     # IAM roles, EKS control plane, access entry
├── environments/
│   ├── dev/                     # backend.tfvars + vars.tfvars for dev
│   ├── qa/                      # backend.tfvars + vars.tfvars for qa
│   └── prd/                     # backend.tfvars + vars.tfvars for prd
├── main.tf                      # Root module — calls vpc and eks modules
└── providers.tf                 # AWS provider + partial S3 backend config
```

The project uses a **single root module** at the repository root. The `environments/<env>/` directories are not separate Terraform root modules — they each contain two configuration files only:

- `backend.tfvars` — environment-specific backend values (S3 bucket, key, region)
- `vars.tfvars` — environment-specific variable values (instance type, node counts)

Running `terraform init -backend-config=environments/dev/backend.tfvars` points Terraform at a separate state key in S3 for that environment. Passing `-var-file=environments/dev/vars.tfvars` at plan/apply time sets the environment-specific sizing. The separate state keys make it impossible for an apply in one environment to read or write another environment's state.

---

## Prerequisites

1. Terraform >= 1.3 installed
2. AWS credentials configured (`aws configure` or environment variables)
3. Verify both: `terraform version` and `aws sts get-caller-identity`

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

After apply, update your kubeconfig and verify the cluster endpoint is reachable:

```bash
aws eks update-kubeconfig --name borsboomh-eks-dev --region af-south-1
kubectl get nodes
```

> Note: the EKS module does not yet provision a worker node group (see Known Limitations). `kubectl get nodes` will return no resources at this stage.

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

> Known issue: the CI matrix declares `prod` as the environment name but the directory is named `prd`. The `prod` job will fail with a missing directory error until the matrix value or the directory name is aligned.

---

## Design Decisions and Trade-offs

**Single root module with var-file environment overrides:** All three environments share one root module and one set of reusable modules. Switching environments requires reinitialising with a different `backend.tfvars` and passing a different `vars.tfvars`. This avoids code duplication at the cost of requiring `-reconfigure` when switching environments on the same machine. An alternative design is a separate root module per environment (one `main.tf` per environment that calls the shared modules), which allows all three to coexist simultaneously without reinitialisation.

**S3 native state locking:** State locking uses S3's built-in locking (`use_lockfile = true`) rather than a DynamoDB table. This removes a bootstrapping dependency — the S3 bucket alone is sufficient, and no second resource needs to exist before state can be used.

**EKS API authentication mode:** The EKS cluster uses `authentication_mode = "API"` and access entries instead of the legacy `aws-auth` ConfigMap. This grants the Terraform caller cluster-admin rights automatically after apply without a separate `kubectl apply` step.

**Public subnets:** Subnets use public addressing. This gives nodes direct outbound internet access to pull container images and reach the EKS API endpoint. In a production system you would use private subnets behind a NAT Gateway to avoid exposing node IPs — public subnets are acceptable for this training exercise.

**Node sizing by environment:** dev uses t3.small (1 node) to minimise cost. qa uses t3.medium (2 nodes) for basic multi-node testing. prd uses t3.large (3 nodes minimum) for workload headroom and rolling update capacity.

---

## Known Limitations

- **No worker node group provisioned.** The EKS module defines `node_instance_type`, `node_desired_size`, `node_min_size`, and `node_max_size` variables, but the `aws_eks_node_group` resource and its associated IAM role are not implemented. The cluster control plane deploys, but no worker nodes join it.

- **VPC networking is incomplete.** The VPC module creates a VPC and three subnets but does not provision an Internet Gateway or route tables. Worker nodes in public subnets require a route (`0.0.0.0/0 -> IGW`) to reach the internet. Without it, nodes cannot pull container images or communicate with the EKS API endpoint.

- **Subnet tagging is missing.** EKS requires subnets to be tagged with `kubernetes.io/cluster/<name>=shared` for subnet auto-discovery by the control plane and load balancer controller. These tags are not applied in the current VPC module. The `cluster_name` variable is accepted by the VPC module but not used.

- **CI workflow environment name mismatch.** The GitHub Actions matrix uses `prod` but the directory is `prd`. The `prod` matrix job will error with a missing directory.

- **`bootstrap/terraform.tfstate` is stored locally.** If it is lost, the S3 bucket would need to be manually imported into a new bootstrap state with `terraform import`.

- **EKS version is pinned to `1.32`** via the module default. Check currently supported versions before applying: `aws eks describe-addon-versions --region af-south-1`.

- **No NAT Gateway.** Acceptable for training; not recommended for production workloads.

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
