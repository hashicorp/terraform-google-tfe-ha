# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Random String for unique names
# ------------------------------
resource "random_pet" "main" {
  length = 1
}

# Store TFE License as secret
# ---------------------------
module "secrets" {
  source = "../../fixtures/secrets"

  license = {
    id   = random_pet.main.id
    path = var.license_file
  }
}

# Standalone, mounted disk
# ------------------------
module "tfe" {
  source = "../../"

  gcp_project_id              = var.gcp_project_id
  distribution                = "ubuntu"
  dns_zone_name               = var.dns_zone_name
  existing_service_account_id = var.existing_service_account_id
  namespace                   = random_pet.main.id
  node_count                  = 1
  fqdn                        = var.fqdn
  load_balancer               = "PUBLIC"
  ssl_certificate_name        = var.ssl_certificate_name
  tfe_license_secret_id       = module.secrets.license_secret
  vm_machine_type             = "n1-standard-4"
}
