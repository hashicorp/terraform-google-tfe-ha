# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "random_pet" "main" {
  length    = 1
  prefix    = "smd"
  separator = "-"
}

# Store TFE License as secret
# ---------------------------
module "secrets" {
  count  = var.license_file == null || !var.is_replicated_deployment ? 0 : 1
  source = "../../fixtures/secrets"

  license = {
    id   = random_pet.main.id
    path = var.license_file
  }
}

resource "tls_private_key" "main" {
  algorithm = "RSA"
}

resource "local_file" "private_key_pem" {
  filename = "${path.module}/work/private-key.pem"

  content         = tls_private_key.main.private_key_pem
  file_permission = "0600"
}

module "tfe" {
  source                        = "../.."
  consolidated_services_enabled = var.consolidated_services_enabled
  disk_path                     = "/opt/hashicorp/data"
  distribution                  = "ubuntu"
  dns_zone_name                 = data.google_dns_managed_zone.main.name
  fqdn                          = "${random_pet.main.id}.${trimsuffix(data.google_dns_managed_zone.main.dns_name, ".")}"
  namespace                     = random_pet.main.id
  node_count                    = 1
  tfe_license_secret_id         = try(module.secrets[0].license_secret, data.tfe_outputs.base.values.license_secret_id)

  existing_service_account_id   = var.existing_service_account_id
  iact_subnet_list              = ["0.0.0.0/0"]
  iact_subnet_time_limit        = 60
  labels                        = local.labels
  load_balancer                 = "PUBLIC"
  operational_mode              = "disk"
  ssl_certificate_name          = data.tfe_outputs.base.values.wildcard_region_ssl_certificate_name
  ssl_certificate_secret        = var.is_replicated_deployment ? null : data.tfe_outputs.base.values.wildcard_ssl_certificate_secret_id
  ssl_private_key_secret        = var.is_replicated_deployment ? null : data.tfe_outputs.base.values.wildcard_ssl_private_key_secret_id
  vm_disk_source_image          = data.google_compute_image.ubuntu.self_link
  vm_machine_type               = "n1-standard-4"
  vm_metadata = {
    "ssh-keys" = "${local.ssh_user}:${tls_private_key.main.public_key_openssh} ${local.ssh_user}"
  }

  # FDO Specific Values
  is_replicated_deployment  = var.is_replicated_deployment
  hc_license                = var.hc_license
  http_port                 = 8080
  https_port                = 8443
  license_reporting_opt_out = true
  registry_password         = var.registry_password
  registry_username         = var.registry_username
  tfe_image                 = "quay.io/hashicorp/terraform-enterprise:${var.tfe_image_tag}"
}


resource "null_resource" "wait_for_instances" {
  count = local.enable_ssh_config
  triggers = {
    self_link = module.tfe.vm_mig.instance_group
  }

  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "local_file" "ssh_config" {
  count    = local.enable_ssh_config
  filename = "${path.module}/work/ssh-config"

  content = templatefile(
    "${path.module}/templates/ssh-config.tpl",
    {
      instance      = data.null_data_source.instance[0].outputs
      identity_file = local_file.private_key_pem.filename
      user          = local.ssh_user
    }
  )
}
