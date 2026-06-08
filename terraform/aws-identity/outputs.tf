output "trust_anchor_arn" {
  value = aws_rolesanywhere_trust_anchor.onprem_k8s.arn
}

output "vault_role_arn" {
  value = aws_iam_role.vault.arn
}

output "vault_profile_arn" {
  value = aws_rolesanywhere_profile.vault.arn
}

output "vault_kms_key_id" {
  value = aws_kms_key.vault_unseal.key_id
}

output "vault_kms_alias" {
  value = aws_kms_alias.vault_unseal.name
}

output "velero_role_arn" {
  value = aws_iam_role.velero.arn
}

output "velero_profile_arn" {
  value = aws_rolesanywhere_profile.velero.arn
}

output "velero_bucket" {
  value = aws_s3_bucket.velero.bucket
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "external_secrets_profile_arn" {
  value = aws_rolesanywhere_profile.external_secrets.arn
}

output "cert_manager_pca_role_arn" {
  value = aws_iam_role.cert_manager_pca.arn
}

output "cert_manager_pca_profile_arn" {
  value = aws_rolesanywhere_profile.cert_manager_pca.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

output "external_dns_profile_arn" {
  value = aws_rolesanywhere_profile.external_dns.arn
}
