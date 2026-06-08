resource "aws_kms_key" "vault_unseal" {
  description             = "${local.name_prefix} Vault auto-unseal"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "${local.name_prefix}-vault-auto-unseal"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${local.name_prefix}-vault-auto-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_s3_bucket" "velero" {
  bucket = "${local.name_prefix}-velero-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${local.name_prefix}-velero"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "vault" {
  name                 = "${local.name_prefix}-vault"
  assume_role_policy   = data.aws_iam_policy_document.rolesanywhere_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "velero" {
  name                 = "${local.name_prefix}-velero"
  assume_role_policy   = data.aws_iam_policy_document.rolesanywhere_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "external_secrets" {
  name                 = "${local.name_prefix}-external-secrets"
  assume_role_policy   = data.aws_iam_policy_document.rolesanywhere_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "cert_manager_pca" {
  name                 = "${local.name_prefix}-cert-manager-pca"
  assume_role_policy   = data.aws_iam_policy_document.rolesanywhere_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "external_dns" {
  name                 = "${local.name_prefix}-external-dns"
  assume_role_policy   = data.aws_iam_policy_document.rolesanywhere_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "vault" {
  statement {
    sid    = "VaultAutoUnseal"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]

    resources = [
      aws_kms_key.vault_unseal.arn
    ]
  }
}

resource "aws_iam_policy" "vault" {
  name   = "${local.name_prefix}-vault"
  policy = data.aws_iam_policy_document.vault.json
}

resource "aws_iam_role_policy_attachment" "vault" {
  role       = aws_iam_role.vault.name
  policy_arn = aws_iam_policy.vault.arn
}

data "aws_iam_policy_document" "velero" {
  statement {
    sid    = "VeleroS3Backup"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]

    resources = [
      aws_s3_bucket.velero.arn,
      "${aws_s3_bucket.velero.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "velero" {
  name   = "${local.name_prefix}-velero"
  policy = data.aws_iam_policy_document.velero.json
}

resource "aws_iam_role_policy_attachment" "velero" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velero.arn
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid    = "ReadSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${local.name_prefix}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

data "aws_iam_policy_document" "cert_manager_pca" {
  statement {
    sid    = "IssueCertificatesFromPCA"
    effect = "Allow"

    actions = [
      "acm-pca:DescribeCertificateAuthority",
      "acm-pca:GetCertificate",
      "acm-pca:IssueCertificate"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "cert_manager_pca" {
  name   = "${local.name_prefix}-cert-manager-pca"
  policy = data.aws_iam_policy_document.cert_manager_pca.json
}

resource "aws_iam_role_policy_attachment" "cert_manager_pca" {
  role       = aws_iam_role.cert_manager_pca.name
  policy_arn = aws_iam_policy.cert_manager_pca.arn
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    sid    = "ListHostedZones"
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ChangeRecords"
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets"
    ]

    resources = [
      "arn:aws:route53:::hostedzone/*"
    ]
  }
}

resource "aws_iam_policy" "external_dns" {
  name   = "${local.name_prefix}-external-dns"
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

resource "aws_rolesanywhere_profile" "vault" {
  name      = "${local.name_prefix}-vault"
  enabled   = true
  role_arns = [aws_iam_role.vault.arn]
}

resource "aws_rolesanywhere_profile" "velero" {
  name      = "${local.name_prefix}-velero"
  enabled   = true
  role_arns = [aws_iam_role.velero.arn]
}

resource "aws_rolesanywhere_profile" "external_secrets" {
  name      = "${local.name_prefix}-external-secrets"
  enabled   = true
  role_arns = [aws_iam_role.external_secrets.arn]
}

resource "aws_rolesanywhere_profile" "cert_manager_pca" {
  name      = "${local.name_prefix}-cert-manager-pca"
  enabled   = true
  role_arns = [aws_iam_role.cert_manager_pca.arn]
}

resource "aws_rolesanywhere_profile" "external_dns" {
  name      = "${local.name_prefix}-external-dns"
  enabled   = true
  role_arns = [aws_iam_role.external_dns.arn]
}
