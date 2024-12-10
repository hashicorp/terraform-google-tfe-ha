# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module "project_factory_project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 14.0"

  project_id = null

  activate_apis               = local.activate_apis
  disable_dependent_services  = false
  disable_services_on_destroy = false
}

module "object_storage" {
  source = "./modules/object_storage"

  count = local.enable_object_storage_module ? 1 : 0

  namespace       = var.namespace
  labels          = var.labels
  service_account = module.service_accounts.service_account
}

module "service_accounts" {
  source = "./modules/service_accounts"

  ca_certificate_secret_id    = var.ca_certificate_secret_id
  enable_airgap               = local.enable_airgap
  is_replicated_deployment    = var.is_replicated_deployment
  tfe_license_secret_id       = var.tfe_license_secret_id
  namespace                   = var.namespace
  project                     = var.project
  ssl_certificate_secret      = var.ssl_certificate_secret
  ssl_private_key_secret      = var.ssl_private_key_secret
  existing_service_account_id = var.existing_service_account_id
  depends_on = [
    module.project_factory_project_services
  ]
}

module "networking" {
  source = "./modules/networking"

  count = local.enable_networking_module ? 1 : 0

  enable_active_active     = var.operational_mode == "active-active"
  is_replicated_deployment = var.is_replicated_deployment
  namespace                = var.namespace
  subnet_range             = var.networking_subnet_range
  reserve_subnet_range     = var.networking_reserve_subnet_range
  firewall_ports           = var.networking_firewall_ports
  healthcheck_ips          = var.networking_healthcheck_ips
  service_account          = module.service_accounts.service_account
  ip_allow_list            = var.networking_ip_allow_list
  ssh_source_ranges        = var.ssh_source_ranges
  depends_on = [
    module.project_factory_project_services
  ]
}

module "database" {
  source = "./modules/database"

  count = local.enable_database_module ? 1 : 0

  dbname                        = var.database_name
  username                      = var.database_user
  machine_type                  = var.database_machine_type
  disk_size                     = var.postgres_disk_size
  availability_type             = var.database_availability_type
  namespace                     = var.namespace
  backup_start_time             = var.database_backup_start_time
  labels                        = var.labels
  service_networking_connection = local.service_networking_connection
  postgres_version              = var.postgres_version

  depends_on = [
    module.project_factory_project_services
  ]
}

module "redis" {
  source = "./modules/redis"

  count = local.enable_redis_module ? 1 : 0

  auth_enabled                  = var.redis_auth_enabled
  namespace                     = var.namespace
  memory_size                   = var.redis_memory_size
  redis_version                 = var.redis_version
  service_networking_connection = local.service_networking_connection
  labels                        = var.labels

  depends_on = [
    module.project_factory_project_services
  ]
}

# ------------------------------------------------------------------------------------
# Docker Compose File Config for TFE on instance(s) using Flexible Deployment Options
# ------------------------------------------------------------------------------------
module "runtime_container_engine_config" {
  source = "git::https://github.com/hashicorp/terraform-random-tfe-utility//modules/runtime_container_engine_config?ref=main"
  count  = var.is_replicated_deployment ? 0 : 1

  license_reporting_opt_out   = var.license_reporting_opt_out
  usage_reporting_opt_out     = var.usage_reporting_opt_out
  hostname                    = local.common_fqdn
  capacity_concurrency        = var.capacity_concurrency
  capacity_cpu                = var.capacity_cpu
  capacity_memory             = var.capacity_memory
  disk_path                   = local.enable_disk ? var.disk_path : null
  iact_subnets                = join(",", var.iact_subnet_list)
  iact_time_limit             = var.iact_subnet_time_limit
  operational_mode            = var.operational_mode
  run_pipeline_image          = var.run_pipeline_image
  tfe_image                   = var.tfe_image
  tfe_license                 = var.hc_license
  tls_ciphers                 = var.tls_ciphers
  tls_version                 = var.tls_vers
  metrics_endpoint_enabled    = var.metrics_endpoint_enabled
  metrics_endpoint_port_http  = var.metrics_endpoint_port_http
  metrics_endpoint_port_https = var.metrics_endpoint_port_https

  cert_file          = "/etc/ssl/private/terraform-enterprise/cert.pem"
  key_file           = "/etc/ssl/private/terraform-enterprise/key.pem"
  tls_ca_bundle_file = var.ca_certificate_secret_id != null ? "/etc/ssl/private/terraform-enterprise/bundle.pem" : null

  database_user       = local.database.user
  database_password   = local.database.password
  database_host       = local.database.netloc
  database_name       = local.database.dbname
  database_parameters = "sslmode=require"

  storage_type       = "google"
  google_bucket      = local.object_storage.bucket
  google_credentials = module.service_accounts.credentials
  google_project     = local.object_storage.project

  http_port       = var.http_port
  https_port      = var.https_port
  http_proxy      = var.proxy_ip != null ? "${var.proxy_ip}:${var.proxy_port}" : null
  https_proxy     = var.proxy_ip != null ? "${var.proxy_ip}:${var.proxy_port}" : null
  no_proxy        = local.extra_no_proxy
  trusted_proxies = local.trusted_proxies

  redis_host     = local.redis.host
  redis_user     = ""
  redis_password = local.redis.password
  redis_use_tls  = var.redis_use_tls
  redis_use_auth = var.redis_auth_enabled

  vault_address     = var.extern_vault_addr
  vault_namespace   = var.extern_vault_namespace
  vault_path        = var.extern_vault_path
  vault_role_id     = var.extern_vault_role_id
  vault_secret_id   = var.extern_vault_secret_id
  vault_token_renew = var.extern_vault_token_renew
}

# ----------------------------------------------------------------------------------------------------------
# User data / cloud init used to install and configure TFE on instance(s) using Flexible Deployment Options
# ----------------------------------------------------------------------------------------------------------
module "tfe_init_fdo" {
  source = "git::https://github.com/hashicorp/terraform-random-tfe-utility//modules/tfe_init?ref=main"
  count  = var.is_replicated_deployment ? 0 : 1

  cloud             = "google"
  distribution      = var.distribution
  disk_path         = var.disk_path
  disk_device_name  = local.disk_device_name
  operational_mode  = var.operational_mode
  custom_image_tag  = var.custom_image_tag
  enable_monitoring = var.enable_monitoring

  ca_certificate_secret_id = var.ca_certificate_secret_id == null ? null : var.ca_certificate_secret_id
  certificate_secret_id    = var.ssl_certificate_secret == null ? null : var.ssl_certificate_secret
  key_secret_id            = var.ssl_private_key_secret == null ? null : var.ssl_private_key_secret

  proxy_ip       = var.proxy_ip
  proxy_port     = var.proxy_port
  extra_no_proxy = local.extra_no_proxy

  registry          = var.registry
  registry_password = var.registry == "images.releases.hashicorp.com" ? var.hc_license : var.registry_password
  registry_username = var.registry_username

  container_runtime_engine = var.container_runtime_engine
  tfe_image                = var.tfe_image
  podman_kube_yaml         = module.runtime_container_engine_config[0].podman_kube_yaml
  docker_compose_yaml      = module.runtime_container_engine_config[0].docker_compose_yaml
}

# -----------------------------------------------------------------------------
# TFE and Replicated settings to pass to the tfe_init_replicated module
# -----------------------------------------------------------------------------
module "settings" {
  source = "git::https://github.com/hashicorp/terraform-random-tfe-utility//modules/settings?ref=main"
  count  = var.is_replicated_deployment ? 1 : 0

  # TFE Base Configuration
  production_type             = var.operational_mode
  disk_path                   = var.disk_path
  iact_subnet_list            = var.iact_subnet_list
  iact_subnet_time_limit      = var.iact_subnet_time_limit
  release_sequence            = var.release_sequence
  tls_vers                    = var.tls_vers
  metrics_endpoint_enabled    = var.metrics_endpoint_enabled
  metrics_endpoint_port_http  = var.metrics_endpoint_port_http
  metrics_endpoint_port_https = var.metrics_endpoint_port_https
  custom_image_tag            = var.custom_image_tag
  custom_agent_image_tag      = var.custom_agent_image_tag
  capacity_concurrency        = var.capacity_concurrency
  capacity_memory             = var.capacity_memory

  extra_no_proxy = local.extra_no_proxy

  trusted_proxies = concat(
    var.trusted_proxies,
    local.trusted_proxies
  )

  # Replicated Base Configuration
  hostname                                  = local.common_fqdn
  tfe_license_bootstrap_airgap_package_path = var.tfe_license_bootstrap_airgap_package_path
  tfe_license_file_location                 = var.tfe_license_file_location
  tls_bootstrap_cert_pathname               = var.tls_bootstrap_cert_pathname
  tls_bootstrap_key_pathname                = var.tls_bootstrap_key_pathname
  bypass_preflight_checks                   = var.bypass_preflight_checks
  hairpin_addressing                        = var.hairpin_addressing

  # Database
  pg_dbname       = local.database.dbname
  pg_netloc       = local.database.netloc
  pg_user         = local.database.user
  pg_password     = local.database.password
  pg_extra_params = "sslmode=require"

  # Redis
  redis_host              = local.redis.host
  redis_pass              = local.redis.password
  redis_use_password_auth = var.redis_auth_enabled
  redis_use_tls           = var.redis_use_tls

  # Storage
  gcs_bucket      = local.object_storage.bucket
  gcs_credentials = module.service_accounts.credentials
  gcs_project     = local.object_storage.project

  # External Vault
  extern_vault_enable      = var.extern_vault_enable
  extern_vault_addr        = var.extern_vault_addr
  extern_vault_role_id     = var.extern_vault_role_id
  extern_vault_secret_id   = var.extern_vault_secret_id
  extern_vault_path        = var.extern_vault_path
  extern_vault_token_renew = var.extern_vault_token_renew
  extern_vault_namespace   = var.extern_vault_namespace
}

# ---------------------------------------------------------------------------------------
# User data / cloud init used to install and configure TFE on instance(s) via Replicated
# ---------------------------------------------------------------------------------------
module "tfe_init_replicated" {
  source = "git::https://github.com/hashicorp/terraform-random-tfe-utility//modules/tfe_init_replicated?ref=main"
  count  = var.is_replicated_deployment ? 1 : 0

  # TFE & Replicated Configuration data
  cloud                    = "google"
  distribution             = var.distribution
  disk_path                = var.disk_path
  disk_device_name         = local.disk_device_name
  tfe_configuration        = module.settings[0].tfe_configuration
  replicated_configuration = module.settings[0].replicated_configuration
  airgap_url               = var.airgap_url
  enable_monitoring        = var.enable_monitoring

  # Secrets
  ca_certificate_secret_id = var.ca_certificate_secret_id == null ? null : var.ca_certificate_secret_id
  certificate_secret_id    = var.ssl_certificate_secret == null ? null : var.ssl_certificate_secret
  key_secret_id            = var.ssl_private_key_secret == null ? null : var.ssl_private_key_secret
  tfe_license_secret_id    = var.tfe_license_secret_id

  # Proxy information
  proxy_ip   = var.proxy_ip
  proxy_port = var.proxy_port
}

module "vm_instance_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "~> 10.0"

  name_prefix = "${var.namespace}-tfe-template-"

  additional_disks = local.enable_disk ? [
    {
      auto_delete  = true
      boot         = false
      device_name  = local.disk_device_name
      disk_labels  = var.labels
      disk_name    = "${var.namespace}-tfe-mounted"
      disk_size_gb = var.vm_mounted_disk_size
      disk_type    = "pd-ssd"
      mode         = "READ_WRITE"
    }
  ] : []
  auto_delete    = true
  can_ip_forward = true
  disk_labels    = var.labels
  disk_type      = var.vm_disk_type
  disk_size_gb   = var.vm_disk_size
  labels         = var.labels
  machine_type   = var.vm_machine_type
  metadata       = var.vm_metadata
  service_account = {
    scopes = ["cloud-platform"]

    email = module.service_accounts.service_account.email
  }
  source_image   = var.vm_disk_source_image
  startup_script = base64decode(var.is_replicated_deployment ? module.tfe_init_replicated[0].tfe_userdata_base64_encoded : module.tfe_init_fdo[0].tfe_userdata_base64_encoded)
  subnetwork     = local.subnetwork.self_link
}

module "vm_mig" {
  source  = "terraform-google-modules/vm/google//modules/mig"
  version = "~> 10.0"

  instance_template = module.vm_instance_template.self_link
  region            = null

  health_check = {
    check_interval_sec  = var.vm_mig_check_interval_sec
    healthy_threshold   = var.vm_mig_healthy_threshold
    host                = null
    initial_delay_sec   = var.vm_mig_initial_delay_sec
    port                = 443
    proxy_header        = null
    request             = null
    request_path        = "/_health_check"
    response            = null
    timeout_sec         = var.vm_mig_timeout_sec
    type                = "https"
    unhealthy_threshold = var.vm_mig_unhealthy_threshold
    enable_logging      = false
  }
  health_check_name = "${var.namespace}-tfe-health-check"
  hostname          = "${var.namespace}-tfe"
  named_ports = concat(
    [{
      name = "https"
      port = 443
    }],
    var.operational_mode == "active-active" && !var.is_replicated_deployment ? [{
      name = "vault"
      port = 8201
    }] : [],
    !(var.operational_mode == "active-active") && var.is_replicated_deployment ? [{
      name = "console"
      port = 8800
    }] : []
  )
  target_size = var.node_count
  # When enabling public ssh access, the instances created by the mig will
  # get a public IP address attached.
  stateful_ips = var.enable_public_ssh_access ? [
    {
      interface_name = "nic0"
      delete_rule    = "ON_PERMANENT_INSTANCE_DELETION"
      is_external    = true
    }
  ] : []

  # When enabling stateful properties in a mig, the update_policy block is required.
  # This block is used to specify how the mig should handle updates to the instances.
  # In this case, we are using an opportunistic update policy to minimize the impact
  # of updates to the instances when the mig is for replicated. When the mig is for
  # FDO we use a replace update policy to ensure that the instances are replaced.
  update_policy = var.enable_public_ssh_access ? [
    {
      type                         = "OPPORTUNISTIC"
      instance_redistribution_type = "NONE"
      minimal_action               = var.is_replicated_deployment ? "RESTART" : "REPLACE"
      max_unavailable_fixed        = 3
      max_surge_fixed              = null
      max_surge_percent            = null
      max_unavailable_percent      = null
      min_ready_sec                = null
      replacement_method           = null
    }
  ] : []
}

resource "google_compute_address" "private" {
  count = var.load_balancer != "PUBLIC" ? 1 : 0

  name         = "${var.namespace}-tfe-private-lb"
  subnetwork   = local.subnetwork.self_link
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}

module "private_load_balancer" {
  count  = var.load_balancer == "PRIVATE" ? 1 : 0
  source = "./modules/private_load_balancer"

  namespace            = var.namespace
  fqdn                 = local.full_fqdn
  instance_group       = module.vm_mig.instance_group
  ssl_certificate_name = var.ssl_certificate_name
  dns_zone_name        = var.dns_zone_name
  labels               = var.labels
  subnetwork           = local.subnetwork
  dns_create_record    = var.dns_create_record
  ip_address           = google_compute_address.private[0].address
}

module "private_tcp_load_balancer" {
  count  = var.load_balancer == "PRIVATE_TCP" ? 1 : 0
  source = "./modules/private_tcp_load_balancer"

  namespace         = var.namespace
  fqdn              = local.full_fqdn
  instance_group    = module.vm_mig.instance_group
  dns_zone_name     = var.dns_zone_name
  labels            = var.labels
  subnetwork        = local.subnetwork
  dns_create_record = var.dns_create_record
  ip_address        = google_compute_address.private[0].address
}


resource "google_compute_global_address" "public" {
  count = var.load_balancer == "PUBLIC" ? 1 : 0

  name = "${var.namespace}-tfe-public-lb"

  description = "The global address of the public load balancer for TFE."
}

module "load_balancer" {
  count  = var.load_balancer == "PUBLIC" ? 1 : 0
  source = "./modules/load_balancer"

  labels               = var.labels
  namespace            = var.namespace
  fqdn                 = local.full_fqdn
  instance_group       = module.vm_mig.instance_group
  ssl_certificate_name = var.ssl_certificate_name
  dns_zone_name        = var.dns_zone_name
  dns_create_record    = var.dns_create_record
  ip_address           = google_compute_global_address.public[0].address
}
