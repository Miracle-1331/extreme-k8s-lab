variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "miracle"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ca_bundle_pem_path" {
  type        = string
  description = "PEM CA bundle trusted by IAM Roles Anywhere."
}
