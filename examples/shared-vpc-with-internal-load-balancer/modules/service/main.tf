# Create a storage bucket in which application state will be stored.
module "storage" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/storage"

  prefix                = var.prefix
  service_account_email = var.service_account_storage_email

  labels = var.labels
}

resource "google_storage_bucket" "ssl" {
  name = "${var.prefix}ssl"

  bucket_policy_only = true
  force_destroy      = true
  labels             = var.labels
}

resource "google_storage_bucket_iam_member" "ssl" {
  bucket = google_storage_bucket.ssl.name
  member = "allUsers"
  role   = "roles/storage.legacyObjectReader"
}

resource "google_storage_bucket_object" "ssl_bundle" {
  bucket = google_storage_bucket.ssl.name
  name   = "${var.prefix}ssl-bundle.pem"

  source = var.ssl_bundle_file
}

# Create a PostgreSQL database in which application data will be stored.
module "postgresql" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/postgresql"

  prefix                = var.prefix
  vpc_address_name      = var.vpc_postgresql_address_name
  vpc_network_self_link = var.vpc_network_self_link

  labels = var.labels
}

# Generate the application configuration.
module "application" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/application"

  dns_fqdn                                = module.dns.fqdn
  postgresql_database_instance_address    = module.postgresql.database_instance.private_ip_address
  postgresql_database_name                = module.postgresql.database.name
  postgresql_user_name                    = module.postgresql.user.name
  postgresql_user_password                = module.postgresql.user.password
  service_account_storage_key_private_key = var.service_account_storage_key_private_key
  storage_bucket_name                     = module.storage.bucket.name
  storage_bucket_project                  = module.storage.bucket.project
}

# Generate the cloud-init configuration.
module "cloud_init" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/cloud-init"

  application_config                             = module.application.config
  primaries_kubernetes_api_load_balancer_address = module.primaries.kubernetes_api_load_balancer_address.address
  license_file                                   = var.cloud_init_license_file
  vpc_cluster_assistant_tcp_port                 = var.vpc_cluster_assistant_tcp_port
  vpc_install_dashboard_tcp_port                 = var.vpc_install_dashboard_tcp_port
  vpc_kubernetes_tcp_port                        = var.vpc_kubernetes_tcp_port
}

# Create the primaries.
module "primaries" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/primaries"

  cloud_init_configs                  = module.cloud_init.primaries_configs
  prefix                              = var.prefix
  service_account_email               = var.service_account_primaries_email
  service_account_load_balancer_email = var.service_account_primaries_load_balancer_email
  vpc_application_tcp_port            = var.vpc_application_tcp_port
  vpc_cluster_assistant_tcp_port      = var.vpc_cluster_assistant_tcp_port
  vpc_install_dashboard_tcp_port      = var.vpc_install_dashboard_tcp_port
  vpc_kubernetes_tcp_port             = var.vpc_kubernetes_tcp_port
  vpc_network_self_link               = var.vpc_network_self_link
  vpc_subnetwork_project              = var.vpc_subnetwork_project
  vpc_subnetwork_self_link            = var.vpc_subnetwork_self_link

  labels = var.labels
}

# Create the secondaries.
module "secondaries" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/secondaries"

  cloud_init_config              = module.cloud_init.secondaries_config
  prefix                         = var.prefix
  service_account_email          = var.service_account_secondaries_email
  vpc_application_tcp_port       = var.vpc_application_tcp_port
  vpc_kubernetes_tcp_port        = var.vpc_kubernetes_tcp_port
  vpc_network_self_link          = var.vpc_network_self_link
  vpc_install_dashboard_tcp_port = var.vpc_install_dashboard_tcp_port
  vpc_subnetwork_project         = var.vpc_subnetwork_project
  vpc_subnetwork_self_link       = var.vpc_subnetwork_self_link

  labels = var.labels
}

# Create an internal load balancer which directs traffic to the primaries.
module "internal_load_balancer" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/internal-load-balancer"

  prefix                         = var.prefix
  primaries_addresses            = module.primaries.addresses[*].address
  service_account_email          = var.service_account_internal_load_balancer_email
  ssl_bundle_url                 = "https://storage.googleapis.com/${google_storage_bucket.ssl.name}/${google_storage_bucket_object.ssl_bundle.output_name}"
  vpc_application_tcp_port       = var.vpc_application_tcp_port
  vpc_install_dashboard_tcp_port = var.vpc_install_dashboard_tcp_port
  vpc_subnetwork_project         = var.vpc_subnetwork_project
  vpc_subnetwork_self_link       = var.vpc_subnetwork_self_link

  labels = var.labels
}

# Configures DNS entries for the load balancer.
module "dns" {
  source = "github.com/hashicorp/terraform-google-terraform-enterprise?ref=internal-preview//modules/dns"

  managed_zone                       = var.dns_managed_zone
  managed_zone_dns_name              = var.dns_managed_zone_dns_name
  vpc_external_load_balancer_address = var.vpc_external_load_balancer_address
}