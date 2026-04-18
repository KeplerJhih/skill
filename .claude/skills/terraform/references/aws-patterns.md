# AWS Terraform Patterns

Common AWS resource patterns for quick reference. Adapt to project requirements.

---

## VPC + Networking

```hcl
# modules/networking/main.tf

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}
```

---

## Security Group Module (Independent)

> **核心原則：SG 永遠獨立成 module，不放在 compute/ecs 內。** 不同角色 VM 需要不同 SG 組合，從第一天就分離。

### Module: `modules/security-groups/variables.tf`

```hcl
variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the security groups will be created"
  type        = string
}

variable "security_groups" {
  description = "Map of security groups to create. Key is the logical role name (e.g. 'web', 'db')."
  type = map(object({
    description = optional(string, "")
    ingress_rules = list(object({
      description = string
      from_port   = number
      to_port     = number
      ip_protocol = string
      cidr_ipv4   = string
    }))
    egress_rules = optional(list(object({
      description = string
      ip_protocol = string
      cidr_ipv4   = string
    })), [{
      description = "Allow all outbound traffic"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }])
  }))
}
```

### Module: `modules/security-groups/main.tf`

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }

  ingress_rules = merge([
    for sg_key, sg in var.security_groups : {
      for idx, rule in sg.ingress_rules :
      "${sg_key}:${idx}" => merge(rule, { sg_key = sg_key })
    }
  ]...)

  egress_rules = merge([
    for sg_key, sg in var.security_groups : {
      for idx, rule in sg.egress_rules :
      "${sg_key}:${idx}" => merge(rule, { sg_key = sg_key })
    }
  ]...)
}

# 用 name（固定名稱），不用 name_prefix（會產生隨機後綴）
resource "aws_security_group" "this" {
  for_each = var.security_groups

  name   = "${local.name_prefix}-${each.key}-sg"
  vpc_id = var.vpc_id
  description = each.value.description != "" ? each.value.description : "SG for ${local.name_prefix} ${each.key}"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${each.key}-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each          = local.ingress_rules
  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  cidr_ipv4         = each.value.cidr_ipv4
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each          = local.egress_rules
  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  ip_protocol       = each.value.ip_protocol
  cidr_ipv4         = each.value.cidr_ipv4
}
```

### Module: `modules/security-groups/outputs.tf`

```hcl
output "security_group_ids" {
  description = "Map of security group key to its ID"
  value       = { for k, v in aws_security_group.this : k => v.id }
}

output "security_group_names" {
  description = "Map of security group key to its name"
  value       = { for k, v in aws_security_group.this : k => v.name }
}

output "security_group_arns" {
  description = "Map of security group key to its ARN"
  value       = { for k, v in aws_security_group.this : k => v.arn }
}
```

### Environment: terraform.tfvars (SG 定義)

```hcl
security_groups = {
  web = {
    description = "Web-facing instances (SSH + HTTP/HTTPS)"
    ingress_rules = [
      { description = "SSH",   from_port = 22,  to_port = 22,  ip_protocol = "tcp", cidr_ipv4 = "0.0.0.0/0" },
      { description = "HTTP",  from_port = 80,  to_port = 80,  ip_protocol = "tcp", cidr_ipv4 = "0.0.0.0/0" },
      { description = "HTTPS", from_port = 443, to_port = 443, ip_protocol = "tcp", cidr_ipv4 = "0.0.0.0/0" },
    ]
  }
  db = {
    description = "Database instances (MySQL from VPC only)"
    ingress_rules = [
      { description = "MySQL", from_port = 3306, to_port = 3306, ip_protocol = "tcp", cidr_ipv4 = "10.1.0.0/16" },
    ]
  }
}
```

### Key Design Decisions (SG Module)

| 決策 | 原因 |
|------|------|
| SG 獨立 module | 不同角色 VM 需要不同 SG 組合，綁在 compute 內無法靈活配置 |
| 用 `name` 不用 `name_prefix` | 避免隨機後綴（如 `...-20260413084749...`），名稱清晰可識別 |
| `for_each` by role key | 一個 SG 對應一個角色（web/db/internal），按需組合 |
| Ingress/egress flatten 為獨立 rule 資源 | 用 `aws_vpc_security_group_*_rule` 取代 inline block，支持精確增刪 |
| Outputs 含 ID + Name + ARN | 方便下游引用和 debug |

---

## EC2 Multi-Instance (for_each)

Use `for_each` + `map(object)` to manage multiple EC2 instances. **SG 由獨立 module 管理**，compute 只接收 SG ID。每台 instance 透過 `security_group_keys` 指定要掛的 SG 角色。

### Module: `modules/compute/variables.tf`

```hcl
variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "instances" {
  description = "Map of EC2 instances to create. Key is the logical name."
  type = map(object({
    subnet_id          = string
    instance_type      = string
    instance_name      = string
    ami_architecture   = optional(string, "arm64")
    root_volume_size   = optional(number, 30)     # >= 30GB（AMI snapshot 通常 30GB）
    key_name           = optional(string, null)
    associate_eip      = optional(bool, true)
    security_group_ids = list(string)              # 由外部 SG module 提供
  }))
}
```

### Module: `modules/compute/main.tf`

```hcl
locals {
  name_prefix   = "${var.project}-${var.environment}"
  common_tags   = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
  architectures = toset([for inst in var.instances : inst.ami_architecture])
}

data "aws_ami" "amazon_linux" {
  for_each    = local.architectures
  most_recent = true
  owners      = ["amazon"]

  filter { name = "name";   values = [each.value == "arm64" ? "al2023-ami-*-arm64" : "al2023-ami-*-x86_64"] }
  filter { name = "virtualization-type"; values = ["hvm"] }
  filter { name = "state";  values = ["available"] }
}

resource "aws_instance" "main" {
  for_each = var.instances

  ami                    = data.aws_ami.amazon_linux[each.value.ami_architecture].id
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = each.value.security_group_ids  # per-instance SG
  key_name               = each.value.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  credit_specification { cpu_credits = "standard" }

  tags        = merge(local.common_tags, { Name = "${local.name_prefix}-${each.value.instance_name}" })
  volume_tags = merge(local.common_tags, { Name = "${local.name_prefix}-${each.value.instance_name}-root" })
}

resource "aws_eip" "main" {
  for_each = { for k, v in var.instances : k => v if v.associate_eip }
  instance = aws_instance.main[each.key].id
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "${local.name_prefix}-${each.value.instance_name}-eip" })
}
```

### Module: `modules/compute/outputs.tf`

```hcl
output "instance_ids" {
  description = "Map of instance key to EC2 instance ID"
  value       = { for k, v in aws_instance.main : k => v.id }
}

output "private_ips" {
  description = "Map of instance key to private IP"
  value       = { for k, v in aws_instance.main : k => v.private_ip }
}

output "public_ips" {
  description = "Map of instance key to public IP (EIP if associated, otherwise instance public IP)"
  value = {
    for k, v in aws_instance.main : k => (
      contains(keys(aws_eip.main), k) ? aws_eip.main[k].public_ip : v.public_ip
    )
  }
}

output "ami_ids" {
  description = "Map of architecture to AMI ID used"
  value       = { for k, v in data.aws_ami.amazon_linux : k => v.id }
}
```

### Environment: `main.tf` (串接 networking → security-groups → compute)

```hcl
locals {
  resolved_instances = {
    for k, v in var.instances : k => {
      subnet_id          = v.subnet_type == "public" ? module.networking.public_subnet_ids[v.subnet_key] : module.networking.private_subnet_ids[v.subnet_key]
      instance_type      = v.instance_type
      instance_name      = v.instance_name
      ami_architecture   = v.ami_architecture
      root_volume_size   = v.root_volume_size
      key_name           = v.key_name
      associate_eip      = v.associate_eip
      security_group_ids = [for sg_key in v.security_group_keys : module.security_groups.security_group_ids[sg_key]]
    }
  }
}

module "networking"      { source = "../../modules/networking"       ... }
module "security_groups" { source = "../../modules/security-groups"  ... }
module "compute"         { source = "../../modules/compute"
  project   = var.project
  environment = var.environment
  instances = local.resolved_instances
}
```

### Environment: `terraform.tfvars`

```hcl
instances = {
  app = {
    subnet_key          = "a"
    subnet_type         = "public"
    instance_type       = "t4g.small"
    instance_name       = "app"
    security_group_keys = ["web"]          # 掛 web SG
  }
  worker = {
    subnet_key          = "a"
    subnet_type         = "private"
    instance_type       = "t4g.medium"
    instance_name       = "worker"
    root_volume_size    = 50
    associate_eip       = false
    security_group_keys = ["web", "db"]    # 可掛多個 SG
  }
}
```

### Key Design Decisions (Compute)

| 決策 | 原因 |
|------|------|
| SG 不在 compute module 內 | 不同角色 VM 需不同 SG，獨立 module 更靈活 |
| Per-instance `security_group_ids` | 每台 VM 可掛不同 SG 組合，不再全域共用 |
| `security_group_keys` in tfvars | 用角色名（`"web"`）而非 SG ID，environment 層 resolve |
| `root_volume_size` 預設 30GB | Amazon Linux 2023 AMI snapshot 為 30GB，低於此值會報錯 |
| AMI 用 `local.architectures` 去重 | 支持混合 arm64/x86_64，同架構只查一次 |
| EIP 條件式 `for_each` | 只有公網機器需要 EIP |
| 改 variables 同步更新 tfvars | 確保 tfvars 是完整配置，不靠隱式 default |

---

## ECS Fargate

```hcl
# modules/compute/ecs.tf

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  tags = local.common_tags
}
```

---

## ALB (Application Load Balancer)

```hcl
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = local.common_tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

---

## RDS (PostgreSQL)

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = local.common_tags
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  multi_az            = var.environment == "prod"
  publicly_accessible = false
  storage_encrypted   = true
  deletion_protection = var.environment == "prod"

  backup_retention_period = var.environment == "prod" ? 7 : 1
  skip_final_snapshot     = var.environment != "prod"

  tags = local.common_tags
}
```

---

## S3 + CloudFront

```hcl
resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_distribution" "assets" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id                = "s3-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.cloudfront_certificate_arn == "" ? true : false
    acm_certificate_arn            = var.cloudfront_certificate_arn != "" ? var.cloudfront_certificate_arn : null
    ssl_support_method             = var.cloudfront_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = local.common_tags
}
```

---

## Route53 DNS

```hcl
data "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
```

---

## Security Group Patterns (Inline — for ALB/ECS scenarios)

> **Note**: 對於 EC2 multi-instance 場景，使用上方的 Security Group Module。
> 以下 inline 模式適用於 ALB/ECS 等有明確層級關係的場景。
> 所有 SG 使用 `name`（固定名稱），不用 `name_prefix`（避免隨機後綴）。

```hcl
# ALB SG — allow HTTP/HTTPS from internet
resource "aws_security_group" "alb" {
  name   = "${local.name_prefix}-alb-sg"
  vpc_id = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  from_port = 80; to_port = 80; ip_protocol = "tcp"; cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  from_port = 443; to_port = 443; ip_protocol = "tcp"; cidr_ipv4 = "0.0.0.0/0"
}

# App SG — allow traffic only from ALB
resource "aws_security_group" "app" {
  name   = "${local.name_prefix}-app-sg"
  vpc_id = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  from_port = var.container_port; to_port = var.container_port; ip_protocol = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

# DB SG — allow traffic only from app
resource "aws_security_group" "db" {
  name   = "${local.name_prefix}-db-sg"
  vpc_id = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-sg" })
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  from_port = 5432; to_port = 5432; ip_protocol = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}
```

---

## IAM Role for ECS

```hcl
# Execution role — pull images, write logs
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role — app-specific permissions
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}
```
