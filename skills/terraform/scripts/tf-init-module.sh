#!/usr/bin/env bash
# tf-init-module.sh — Scaffold a new Terraform module directory
#
# Usage:
#   ./tf-init-module.sh <module-path> [--style aws|gcp]
#   ./tf-init-module.sh infra/modules/networking
#   ./tf-init-module.sh infra/modules/storage --style gcp
#   ./tf-init-module.sh infra/environments/dev --style aws

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <module-path> [--style aws|gcp]"
  echo ""
  echo "Styles:"
  echo "  aws  — Uses project + environment variables, tags (default)"
  echo "  gcp  — Uses project_id + region variables, labels"
  echo ""
  echo "Examples:"
  echo "  $0 infra/modules/networking"
  echo "  $0 infra/modules/storage --style gcp"
  echo "  $0 infra/environments/uat --style gcp"
  exit 1
fi

MODULE_PATH="$1"
MODULE_NAME=$(basename "$MODULE_PATH")
STYLE="aws"

# Parse --style flag
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --style)
      STYLE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$MODULE_PATH"

if [ "$STYLE" = "gcp" ]; then
  # --- GCP style ---
  cat > "$MODULE_PATH/main.tf" << 'EOF'
# Resources go here
EOF

  cat > "$MODULE_PATH/variables.tf" << 'EOF'
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}
EOF

  cat > "$MODULE_PATH/outputs.tf" << EOF
# ${MODULE_NAME} outputs
EOF

  if [[ "$MODULE_PATH" == *"environments"* ]]; then
    cat > "$MODULE_PATH/providers.tf" << 'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
EOF

    cat > "$MODULE_PATH/backend.tf" << 'EOF'
terraform {
  backend "gcs" {
    # bucket = "{project}-terraform-state"
    # prefix = "{env}"
  }
}
EOF

    cat > "$MODULE_PATH/terraform.tfvars" << EOF
project_id = ""
region     = ""
EOF
  fi

else
  # --- AWS style (default) ---
  cat > "$MODULE_PATH/main.tf" << 'EOF'
locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
EOF

  cat > "$MODULE_PATH/variables.tf" << 'EOF'
variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "region" {
  description = "Cloud provider region"
  type        = string
}
EOF

  cat > "$MODULE_PATH/outputs.tf" << EOF
# ${MODULE_NAME} outputs
EOF

  if [[ "$MODULE_PATH" == *"environments"* ]]; then
    cat > "$MODULE_PATH/providers.tf" << 'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
EOF

    cat > "$MODULE_PATH/backend.tf" << 'EOF'
terraform {
  backend "s3" {
    # bucket         = "{project}-terraform-state"
    # key            = "{env}/terraform.tfstate"
    # region         = "ap-northeast-1"
    # encrypt        = true
    # dynamodb_table = "{project}-terraform-lock"
  }
}
EOF

    cat > "$MODULE_PATH/terraform.tfvars" << EOF
project     = ""
environment = "$(basename "$MODULE_PATH")"
region      = ""
EOF
  fi
fi

echo "Module scaffolded at: $MODULE_PATH (style: $STYLE)"
ls -la "$MODULE_PATH"
