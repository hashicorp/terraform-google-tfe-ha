resource "random_pet" "main" {
  length    = 1
  prefix    = "praa"
  separator = "-"
}

resource "google_service_account" "http_proxy" {
  account_id = local.name

  description  = "The service account of the HTTP proxy for TFE."
  display_name = "TFE HTTP Proxy"
}

resource "google_project_iam_member" "log_writer" {
  member = "serviceAccount:${google_service_account.http_proxy.email}"
  role   = "roles/logging.logWriter"
}

module "test_proxy_init" {
  source = "github.com/hashicorp/terraform-random-tfe-utility//fixtures/test_proxy_init?ref=aaron-lane-fixture-test-proxy-init"
}

resource "google_compute_firewall" "http_proxy" {
  name    = local.name
  network = module.tfe.network.self_link

  description             = "The firewall which allows internal access to the HTTP proxy."
  direction               = "INGRESS"
  source_ranges           = [module.tfe.subnetwork.ip_cidr_range]
  target_service_accounts = [google_service_account.http_proxy.email]

  allow {
    protocol = "tcp"

    ports = [module.test_proxy_init.squid.http_port]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "ssh" {
  name    = "${local.name}-ssh"
  network = module.tfe.network.self_link

  description             = "The firewall which allows the ingress of Identity-Aware Proxy SSH traffic to the HTTP proxy."
  direction               = "INGRESS"
  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.http_proxy.email]

  allow {
    protocol = "tcp"

    ports = ["22"]
  }
}

resource "google_compute_instance" "http_proxy" {
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.id
    }
  }

  machine_type = "n1-standard-2"
  name         = local.name

  description             = "An HTTP proxy for TFE."
  metadata_startup_script = module.test_proxy_init.squid.user_data_script_base64_encoded

  network_interface {
    subnetwork = module.tfe.subnetwork.self_link
  }

  service_account {
    scopes = ["cloud-platform"]

    email = google_service_account.http_proxy.email
  }

  labels = local.labels

}

module "tfe" {
  source = "../.."

  dns_zone_name        = data.google_dns_managed_zone.main.name
  fqdn                 = "private-active-active.${data.google_dns_managed_zone.main.dns_name}"
  namespace            = random_pet.main.id
  node_count           = 2
  license_secret       = data.tfe_outputs.base.values.license_secret_id
  ssl_certificate_name = data.tfe_outputs.base.values.wildcard_region_ssl_certificate_name
  labels               = local.labels

  iact_subnet_list       = ["${google_compute_instance.http_proxy.network_interface[0].network_ip}/32"]
  iact_subnet_time_limit = 1440
  load_balancer          = "PRIVATE"
  proxy_ip               = "${google_compute_instance.http_proxy.network_interface[0].network_ip}:${module.test_proxy_init.squid.http_port}"
  redis_auth_enabled     = true
  vm_disk_source_image   = data.google_compute_image.rhel.self_link
  vm_machine_type        = "n1-standard-16"
}
