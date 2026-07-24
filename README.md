# borsboomh-terraform

Multi-environment EKS deployment on AWS using Terraform. Provisions a VPC and EKS cluster (control plane + managed node group) in three independent environments: dev, qa, and prod.

---

## Project Structure

```
borsboomh-terraform/
├── bootstrap/          # Run once to create the S3 bucket and DynamoDB lock table
├── modules/
│   ├── vpc/            # VPC, subnets, Internet Gateway, route tables
│   └── eks/            # IAM roles, EKS cluster, access entry, node group
└── environments/
    ├── dev/            # Independent Terraform root module for dev
    ├── qa/             # Independent Terraform root module for qa
    └── prod/           # Independent Terraform root module for prod
```

Each `environments/<env>/` directory is a self-contained Terraform root module. Running `terraform apply` inside `environments/dev/` targets only dev state and resources — it cannot affect qa or prod. The modules are written once and called three times with different inputs, avoiding code duplication while allowing per-environment configuration (instance sizes, node counts).

---

## Prerequisites

1. Terraform >= 1.3 installed
2. AWS credentials configured (`aws configure` or environment variables)
3. Verify both: `terraform version` and `aws sts get-caller-identity`

---

## Step 1 — Run Bootstrap (once only)

The S3 bucket and DynamoDB table for remote state must exist before any environment can initialise. This is the classic Terraform bootstrapping problem: you cannot use remote state to store the infrastructure that provides your remote state.

The `bootstrap/` directory solves this with a local-state configuration that runs once:

```bash
cd bootstrap
terraform init
terraform plan
terraform apply
```

Confirm the output shows `state_bucket_name = "borsboomh-tfstate"` and `lock_table_name = "borsboomh-tfstate-locks"`.

The `bootstrap/terraform.tfstate` file is created locally. Do not commit it and do not delete it — it is your only record of the bootstrap infrastructure.

---

## Step 2 — Deploy an Environment

Run the following steps for each environment (dev first, then qa, then prod):

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

After a successful apply, update your kubeconfig and verify the cluster is reachable:

```bash
aws eks update-kubeconfig --name borsboomh-eks-dev --region af-south-1
kubectl get nodes
```

Repeat for qa and prod:

```bash
cd ../qa  && terraform init && terraform plan && terraform apply
cd ../prod && terraform init && terraform plan && terraform apply
```

---

## Remote State Strategy

All three environments share a single S3 bucket (`borsboomh-tfstate`) but store state in separate objects:

| Environment | State key |
|---|---|
| dev  | `dev/terraform.tfstate`  |
| qa   | `qa/terraform.tfstate`   |
| prod | `prod/terraform.tfstate` |

State locking uses S3 native locking (`use_lockfile = true`). Terraform writes a `.tflock` object alongside each state file in the bucket. No DynamoDB table is required. Each environment's `backend.tf` specifies its own key, making it physically impossible for a `terraform apply` in one environment to read or write another environment's state file.

---

## Design Decisions and Trade-offs

**Public subnets:** Worker nodes use public subnets with `map_public_ip_on_launch = true`. This gives nodes direct outbound internet access to pull container images and reach the EKS API endpoint. In a production system you would use private subnets behind a NAT Gateway to avoid exposing node IPs — public subnets are acceptable for this training exercise.

**Shared DynamoDB lock table:** All three environments use one lock table with separate lock keys. An alternative is one table per environment, but a single table is simpler to manage and the lock keys are namespaced by S3 key so there is no risk of cross-environment lock conflicts.

**Node sizing by environment:** dev uses t3.small (1 node) to minimise cost. qa uses t3.medium (2 nodes) for basic multi-node testing. prod uses t3.large (3 nodes minimum) for workload headroom and rolling update capacity.

**Environment configs use locals, not tfvars:** Each `environments/<env>/main.tf` hardcodes its environment name and sizing as locals. This prevents any possibility of accidentally passing a dev tfvars file to a prod apply.

**terraform destroy does not remove the state bucket:** The S3 bucket and DynamoDB table are created by `bootstrap/`, not by any environment config. Destroying an environment removes only its VPC and EKS resources — the state infrastructure persists. This is intentional: destroying the bucket would destroy the state for all other environments.

---

## Known Limitations

- The `bootstrap/terraform.tfstate` file is stored locally. If it is lost, the S3 bucket and DynamoDB table would need to be manually imported back into a new bootstrap state with `terraform import`.
- The EKS version is pinned to `1.32` in all environments. Check currently supported versions before applying: `aws eks describe-addon-versions --region af-south-1`.
- No NAT Gateway — worker nodes have public IPs. Acceptable for training; not recommended for production workloads.

---

## Teardown

To destroy a single environment:

```bash
cd environments/dev
terraform destroy
```

The state bucket and DynamoDB table are not destroyed. To remove the bootstrap infrastructure after all environments are destroyed:

```bash
# Empty the S3 bucket first (Terraform cannot delete a non-empty versioned bucket)
aws s3 rm s3://borsboomh-tfstate --recursive
cd bootstrap
terraform destroy
```
