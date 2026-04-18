# Terraform Security Checklist

Use this checklist when reviewing or writing Terraform configurations.

---

## 1. Secrets & Credentials

| Check | Severity |
|-------|----------|
| No hardcoded passwords, API keys, or tokens in `.tf` files | CRITICAL |
| Sensitive variables marked with `sensitive = true` | HIGH |
| Sensitive outputs marked with `sensitive = true` | HIGH |
| `.tfstate` excluded from version control (`.gitignore`) | CRITICAL |
| `terraform.tfvars` with secrets excluded from version control | HIGH |
| No secrets in `default` values of variables | CRITICAL |

```hcl
# GOOD
variable "db_password" {
  type      = string
  sensitive = true
  # No default!
}

# BAD
variable "db_password" {
  default = "my-secret-password"
}
```

---

## 2. Network Security

### AWS

| Check | Severity |
|-------|----------|
| Security groups do not allow `0.0.0.0/0` on non-public ports | HIGH |
| No SSH (22) or RDP (3389) open to `0.0.0.0/0` | CRITICAL |
| Database security groups only allow app security groups | HIGH |
| ALB security groups restrict to 80/443 only | MEDIUM |
| Private subnets use NAT Gateway, not direct internet access | HIGH |
| VPC Flow Logs enabled for prod | MEDIUM |

### GCP

| Check | Severity |
|-------|----------|
| Firewall rules use specific source ranges, not `0.0.0.0/0` | HIGH |
| Default deny-all ingress rule exists | HIGH |
| Cloud SQL `ipv4_enabled = false` (use private IP) | HIGH |
| Cloud Run services not publicly accessible unless intended | HIGH |
| VPC Access Connector used for Cloud Run to private resources | MEDIUM |

---

## 3. Encryption

| Check | Cloud | Severity |
|-------|-------|----------|
| S3 bucket encryption enabled (SSE-S3 or SSE-KMS) | AWS | HIGH |
| S3 `block_public_access` enabled | AWS | CRITICAL |
| RDS `storage_encrypted = true` | AWS | HIGH |
| Cloud SQL encryption (default in GCP, verify not disabled) | GCP | HIGH |
| Cloud Storage uniform bucket-level access enabled | GCP | HIGH |
| ALB/LB uses TLS 1.2+ only | Both | HIGH |
| CloudFront `minimum_protocol_version = "TLSv1.2_2021"` | AWS | HIGH |

---

## 4. IAM & Access Control

### AWS

| Check | Severity |
|-------|----------|
| No `*` in IAM policy actions for production | CRITICAL |
| No `*` in IAM policy resources for production | HIGH |
| ECS tasks use separate execution and task roles | HIGH |
| S3 bucket policies follow least privilege | HIGH |
| Cross-account access explicitly documented | MEDIUM |

### GCP

| Check | Severity |
|-------|----------|
| Service accounts have minimal roles | HIGH |
| No `roles/owner` or `roles/editor` on service accounts | CRITICAL |
| Cloud Run uses dedicated service accounts, not default | HIGH |
| Workload Identity used for GKE (not key files) | HIGH |

---

## 5. Service Account & Key Management

| Check | Cloud | Severity |
|-------|-------|----------|
| SA keys not generated via `google_service_account_key` (stored in state) | GCP | HIGH |
| Prefer `gcloud iam service-accounts keys create` (key stays local) | GCP | HIGH |
| Prefer Workload Identity / Federation over key files | GCP | HIGH |
| AWS access keys not created via `aws_iam_access_key` (stored in state) | AWS | HIGH |
| Prefer IAM roles + instance profiles over static credentials | AWS | HIGH |
| Key files excluded from version control (`.gitignore`) | Both | CRITICAL |
| Key rotation policy documented or automated | Both | MEDIUM |
| Unused keys regularly audited and revoked | Both | MEDIUM |

### Why Avoid Keys in Terraform State?

`google_service_account_key` and `aws_iam_access_key` store the private key / secret in plain text within `terraform.tfstate`. Even with remote encrypted backends, anyone with state access can extract credentials.

**Decision matrix:**

| Scenario | Recommended Approach |
|----------|---------------------|
| GKE workloads | Workload Identity (no keys) |
| GitHub Actions / external CI | Workload Identity Federation (no keys) |
| Dev/staging one-off access | `gcloud` / `aws` CLI key generation (key never in state) |
| Automated rotation required | Terraform `google_service_account_key` with `keepers` + encrypted state |

---

## 6. Database Security

| Check | Cloud | Severity |
|-------|-------|----------|
| `publicly_accessible = false` | AWS RDS | CRITICAL |
| `deletion_protection = true` in prod | Both | HIGH |
| Automated backups enabled | Both | HIGH |
| `skip_final_snapshot = false` in prod | AWS RDS | HIGH |
| Point-in-time recovery enabled in prod | Both | MEDIUM |
| Database in private subnet only | Both | HIGH |
| Connection logging enabled | Both | MEDIUM |

---

## 7. Compute Security

| Check | Cloud | Severity |
|-------|-------|----------|
| Containers run as non-root user | Both | HIGH |
| ECS/Cloud Run in private subnets | Both | HIGH |
| Container images from trusted registries | Both | HIGH |
| Health checks configured | Both | MEDIUM |
| Resource limits set (CPU/memory) | Both | MEDIUM |
| Auto-scaling configured with max limits | Both | MEDIUM |

---

## 8. State & Operations

| Check | Severity |
|-------|----------|
| State file not in version control | CRITICAL |
| State encryption enabled (if remote backend) | HIGH |
| State locking enabled (if remote backend) | HIGH |
| `terraform plan` reviewed before `apply` | HIGH |
| No `terraform destroy` without explicit confirmation | HIGH |
| Provider versions pinned | MEDIUM |
| Terraform version pinned (`required_version`) | MEDIUM |

---

## 9. Tagging & Labeling

| Check | Severity |
|-------|----------|
| All resources tagged with `Project` | MEDIUM |
| All resources tagged with `Environment` | MEDIUM |
| All resources tagged with `ManagedBy = terraform` | MEDIUM |
| Cost allocation tags present for billing | LOW |

---

## 10. High Availability (Production)

| Check | Cloud | Severity |
|-------|-------|----------|
| Multi-AZ for RDS | AWS | HIGH |
| Regional availability for Cloud SQL | GCP | HIGH |
| Multiple subnets across AZs | AWS | HIGH |
| Auto-scaling with min > 0 for prod | Both | HIGH |
| Load balancer health checks configured | Both | HIGH |

---

## Review Process

When performing a Terraform security review:

1. **Scan all `.tf` files** for hardcoded secrets (strings that look like keys, passwords, tokens)
2. **Check variables.tf** — all sensitive inputs marked `sensitive = true`
3. **Check outputs.tf** — sensitive outputs marked `sensitive = true`
4. **Review network rules** — security groups / firewall rules follow least privilege
5. **Verify encryption** — storage, database, and transit encryption enabled
6. **Check IAM** — no wildcard permissions, dedicated roles per service
7. **Check SA key management** — no keys in state, prefer Workload Identity / gcloud
8. **Verify state safety** — `.gitignore` excludes state files
9. **Check production hardening** — deletion protection, backups, multi-AZ

Report findings in a table format:

```
| # | File | Line | Issue | Severity | Recommendation |
|---|------|------|-------|----------|----------------|
| 1 | main.tf | 42 | SG allows 0.0.0.0/0 on port 22 | CRITICAL | Restrict to bastion IP |
| 2 | variables.tf | 15 | db_password not marked sensitive | HIGH | Add sensitive = true |
```
