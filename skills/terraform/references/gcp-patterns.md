# GCP Terraform Patterns

Common GCP resource patterns for quick reference. Adapt to project requirements.

---

## VPC Network

```hcl
resource "google_compute_network" "main" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "public" {
  for_each = var.public_subnets

  name          = "${local.name_prefix}-public-${each.key}"
  ip_cidr_range = each.value.cidr
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id
}

resource "google_compute_subnetwork" "private" {
  for_each = var.private_subnets

  name                     = "${local.name_prefix}-private-${each.key}"
  ip_cidr_range            = each.value.cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  project                  = var.project_id
  private_ip_google_access = true
}

# Cloud NAT for private subnet outbound
resource "google_compute_router" "main" {
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
  project = var.project_id
}

resource "google_compute_router_nat" "main" {
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                    = subnetwork.value.id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }
}
```

---

## GKE Autopilot

> **重要**：Autopilot 叢集必須明確啟用 `http_load_balancing`，否則 GCE Ingress Controller 不會運作，
> 導致 GCLB Ingress 無法綁定 IP。Autopilot 不會自動啟用此 addon。

```hcl
resource "google_container_cluster" "autopilot" {
  name     = "${local.name_prefix}-gke"
  project  = var.project_id
  location = var.region

  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  # --- 必要 addons ---
  # http_load_balancing 必須明確啟用，否則：
  # - IngressClass "gce" 不會被建立
  # - GCLB Ingress 無法綁定 static IP
  # - default-http-backend 的 NEG 不會被建立
  addons_config {
    http_load_balancing {
      disabled = false
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  ip_allocation_policy {
    # Autopilot 需要 VPC-native 模式
    # 可指定 secondary range 或留空讓 GKE 自動配置
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  deletion_protection = var.environment == "prod"

  labels = local.common_labels
}

# GCLB 使用的 global static IP
resource "google_compute_global_address" "ingress" {
  name    = "${local.name_prefix}-ingress-ip"
  project = var.project_id
}
```

### GKE Autopilot 常見陷阱

| 問題 | 原因 | 解法 |
|------|------|------|
| Ingress 沒有 ADDRESS | `http_load_balancing` 未啟用 | `addons_config` 中設定 `disabled = false` |
| NEG not found 404 | Autopilot 預設使用 NEG，addon 未就緒 | 確認 `http_load_balancing` 已啟用，等待 3-5 分鐘 |
| 無法修改 kube-system | Autopilot 限制 managed namespace | 使用 annotation/values 而非直接 patch |
| IngressClass "gce" 不存在 | ingress controller 未安裝 | 啟用 `http_load_balancing` addon |

---

## Cloud Run

```hcl
resource "google_cloud_run_v2_service" "app" {
  name     = "${local.name_prefix}-app"
  location = var.region
  project  = var.project_id

  template {
    scaling {
      min_instance_count = var.environment == "prod" ? 1 : 0
      max_instance_count = var.max_instances
    }

    containers {
      image = var.container_image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      startup_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        initial_delay_seconds = 10
        period_seconds        = 3
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  labels = local.common_labels
}

# Allow unauthenticated access (for public APIs)
resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

---

## Cloud SQL (PostgreSQL)

```hcl
resource "google_sql_database_instance" "main" {
  name             = "${local.name_prefix}-db"
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id

  settings {
    tier              = var.db_tier
    availability_type = var.environment == "prod" ? "REGIONAL" : "ZONAL"
    disk_autoresize   = true
    disk_size         = var.db_disk_size

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.environment == "prod"
      start_time                     = "03:00"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }
  }

  deletion_protection = var.environment == "prod"

  labels = local.common_labels
}

resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

resource "google_sql_user" "main" {
  name     = var.db_username
  instance = google_sql_database_instance.main.name
  password = var.db_password
  project  = var.project_id
}
```

---

## Cloud Storage + Cloud CDN

```hcl
resource "google_storage_bucket" "assets" {
  name          = "${local.name_prefix}-assets"
  location      = var.region
  project       = var.project_id
  force_destroy = var.environment != "prod"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = local.common_labels
}

# Backend bucket for CDN
resource "google_compute_backend_bucket" "assets" {
  name        = "${local.name_prefix}-assets-backend"
  bucket_name = google_storage_bucket.assets.name
  enable_cdn  = true
  project     = var.project_id

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 3600
    max_ttl           = 86400
    serve_while_stale = 86400
  }
}
```

---

## Cloud Load Balancing (HTTPS)

```hcl
resource "google_compute_global_address" "main" {
  name    = "${local.name_prefix}-lb-ip"
  project = var.project_id
}

resource "google_compute_managed_ssl_certificate" "main" {
  name    = "${local.name_prefix}-cert"
  project = var.project_id

  managed {
    domains = [var.domain_name]
  }
}

resource "google_compute_url_map" "main" {
  name            = "${local.name_prefix}-urlmap"
  default_service = google_compute_backend_service.app.id
  project         = var.project_id
}

resource "google_compute_target_https_proxy" "main" {
  name             = "${local.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main.id]
  project          = var.project_id
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${local.name_prefix}-https-rule"
  target                = google_compute_target_https_proxy.main.id
  ip_address            = google_compute_global_address.main.address
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
  project               = var.project_id
}

# HTTP to HTTPS redirect
resource "google_compute_url_map" "redirect" {
  name    = "${local.name_prefix}-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  name    = "${local.name_prefix}-http-proxy"
  url_map = google_compute_url_map.redirect.id
  project = var.project_id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${local.name_prefix}-http-rule"
  target                = google_compute_target_http_proxy.redirect.id
  ip_address            = google_compute_global_address.main.address
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
  project               = var.project_id
}
```

---

## Cloud DNS

```hcl
resource "google_dns_managed_zone" "main" {
  name     = "${local.name_prefix}-zone"
  dns_name = "${var.domain_name}."
  project  = var.project_id

  labels = local.common_labels
}

resource "google_dns_record_set" "app" {
  name         = "${var.subdomain}.${var.domain_name}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.main.name
  project      = var.project_id

  rrdatas = [google_compute_global_address.main.address]
}
```

---

## VPC Access Connector (for Cloud Run)

```hcl
resource "google_vpc_access_connector" "main" {
  name          = "${local.name_prefix}-connector"
  region        = var.region
  project       = var.project_id
  ip_cidr_range = var.connector_cidr
  network       = google_compute_network.main.name

  min_instances = 2
  max_instances = 3
}
```

---

## Firewall Rules

```hcl
# Allow health checks from GCP load balancer
resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.name_prefix}-allow-health-check"
  network = google_compute_network.main.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = [var.container_port]
  }

  source_ranges = [
    "130.211.0.0/22",  # GCP health check ranges
    "35.191.0.0/16",
  ]

  target_tags = ["app"]
}

# Allow internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal"
  network = google_compute_network.main.name
  project = var.project_id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr]
}

# Deny all ingress by default
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${local.name_prefix}-deny-all-ingress"
  network  = google_compute_network.main.name
  project  = var.project_id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}
```

---

## Service Account

```hcl
resource "google_service_account" "app" {
  account_id   = "${local.name_prefix}-app"
  display_name = "${var.project} ${var.environment} App Service Account"
  project      = var.project_id
}

# Grant only necessary roles
resource "google_project_iam_member" "app_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "app_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

---

## Cloud Storage — Public Access Bucket

For buckets that require public download access (e.g., static assets, public datasets):

```hcl
resource "google_storage_bucket" "public" {
  name     = "${local.name_prefix}-public"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true

  # MUST be "inherited" (not "enforced") to allow public access
  public_access_prevention = "inherited"

  versioning {
    enabled = false
  }
}
```

> **Key difference**: `public_access_prevention = "enforced"` blocks ALL public IAM. You must set it to `"inherited"` before granting `allUsers` access.

---

## Bucket-Level IAM

Prefer `google_storage_bucket_iam_member` over `google_project_iam_member` for bucket-specific access — it follows least privilege by scoping permissions to a single bucket.

```hcl
# Service Account with CRUD on a specific bucket
resource "google_storage_bucket_iam_member" "sa_admin" {
  bucket = google_storage_bucket.public.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.app.email}"
}

# Public read-only access (anyone can download objects)
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.public.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
```

### IAM Scope Comparison

| Scope | Resource | When to use |
|-------|----------|-------------|
| Project-level | `google_project_iam_member` | SA needs access across multiple buckets/resources |
| Bucket-level | `google_storage_bucket_iam_member` | SA needs access to one specific bucket (preferred) |
| Object-level | Object ACLs | Avoid — use uniform bucket-level access instead |

---

## Service Account + Key Management

```hcl
resource "google_service_account" "app" {
  account_id   = "${local.name_prefix}-sa"
  display_name = "App Service Account"
  project      = var.project_id
}
```

### JSON Key Strategy

**Prefer gcloud over Terraform for key generation** — keys created via `google_service_account_key` are stored in Terraform state (base64-encoded), which is a security risk even with remote encrypted state.

```bash
# Generate key via gcloud (key never touches state)
gcloud iam service-accounts keys create ./sa-key.json \
  --iam-account="SA_EMAIL" \
  --project="PROJECT_ID"
```

**When Terraform-managed keys are acceptable**: automated CI/CD pipelines where the state backend is encrypted, access-controlled, and key rotation is automated via `keepers`.

**Best option when available**: Workload Identity (GKE) or Workload Identity Federation (external) — eliminates keys entirely.

| Method | Key in State | Rotation | Best For |
|--------|-------------|----------|----------|
| `gcloud iam service-accounts keys create` | No | Manual | Dev/staging, one-off access |
| `google_service_account_key` resource | Yes | Via `keepers` | CI/CD with encrypted state |
| Workload Identity / Federation | N/A | Automatic | GKE workloads, GitHub Actions |

---

## GCE Multi-Instance (for_each)

> **通用原則**見 `module-conventions.md` § "for_each Module Design"。本段落為 GCP 等價實作。

GCP 版本與 AWS 的關鍵差異：
- GCP 用 `labels` 而非 `tags`，且只支援小寫
- GCP 用 `google_compute_address`（region-scoped）而非 `aws_eip`
- GCP Firewall 是 VPC 層級（用 `target_tags` 篩選），非 instance 層級的 Security Group
- GCP 用 `machine_image` 或 `boot disk image` 而非 AMI

```hcl
# --- variables.tf ---

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "network_id" {
  description = "VPC network self_link or ID"
  type        = string
}

variable "instances" {
  description = "Map of GCE instances to create. Key is the logical name."
  type = map(object({
    machine_type   = string
    subnet_id      = string
    tags           = optional(list(string), [])
    external_ip    = optional(bool, true)
    desired_status = optional(string, "RUNNING")
    disk_size_gb   = optional(number, 20)
  }))
}
```

```hcl
# --- main.tf ---

# Firewall — shared, scoped by target_tags
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = var.network_id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP range
  target_tags   = ["allow-iap-ssh"]
}

# Instances — one per map entry
resource "google_compute_instance" "main" {
  for_each = var.instances

  name         = each.key
  machine_type = each.value.machine_type
  zone         = var.zone
  project      = var.project_id

  desired_status = each.value.desired_status
  tags           = each.value.tags

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = each.value.disk_size_gb
    }
  }

  network_interface {
    subnetwork = each.value.subnet_id

    dynamic "access_config" {
      for_each = each.value.external_ip ? [1] : []
      content {}
    }
  }

  labels = {
    managed-by = "terraform"
  }
}
```

```hcl
# --- outputs.tf ---

output "instance_internal_ips" {
  value = { for k, v in google_compute_instance.main : k => v.network_interface[0].network_ip }
}

output "instance_external_ips" {
  value = {
    for k, v in google_compute_instance.main : k => (
      length(v.network_interface[0].access_config) > 0
        ? v.network_interface[0].access_config[0].nat_ip
        : null
    )
  }
}
```

### GCP vs AWS for_each 差異對照

| 面向 | AWS | GCP |
|------|-----|-----|
| 防火牆範圍 | Security Group（instance 層級） | Firewall Rule（VPC 層級 + `target_tags`） |
| 公網 IP | `aws_eip` + 條件式 `for_each` | `access_config` + `dynamic` block |
| Image 查詢 | `data.aws_ami` + architecture 去重 | 直接用 `image` family（如 `debian-cloud/debian-12`） |
| Labels/Tags | `tags = merge(local.common_tags, {...})` | `labels = {...}`（只支援小寫、無巢狀） |
| 狀態控制 | 無原生支援（需 stop/start 腳本） | `desired_status = "RUNNING"/"TERMINATED"` |

---

## Common Labels

GCP uses `labels` instead of AWS `tags`:

```hcl
locals {
  common_labels = {
    project     = var.project
    environment = var.environment
    managed-by  = "terraform"
  }
}
```

Note: GCP labels only support lowercase letters, numbers, hyphens, and underscores.
