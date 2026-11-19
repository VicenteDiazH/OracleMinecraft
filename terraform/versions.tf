terraform {
  # 1.9+ permite que una validation haga referencia a otras variables
  required_version = ">= 1.9"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0"
    }
  }
}

# Autenticación con API key. Los valores vienen de terraform.tfvars (no versionado).
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
