terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "miracle-tfstate"
    key    = "extreme-lab/dev.tfstate"
    region = "ap-southeast-1"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "extreme-lab-${var.environment}"
}

resource "aws_rolesanywhere_trust_anchor" "onprem_k8s" {
  name    = "${local.name_prefix}-onprem-k8s-ca"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"

    source_data {
      x509_certificate_data = file(var.ca_bundle_pem_path)
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Lab         = "extreme-lab"
  }
}

data "aws_iam_policy_document" "rolesanywhere_trust" {
  statement {
    sid    = "AllowRolesAnywhereAssumeRole"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:SetSourceIdentity",
      "sts:TagSession"
    ]
  }
}
