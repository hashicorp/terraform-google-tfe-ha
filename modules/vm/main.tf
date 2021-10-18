resource "google_compute_region_disk" "mounted_disk" {
  count = var.disk_enabled ? 1 : 0

  name          = "${var.namespace}-tfe-mounted-disk"
  replica_zones = local.zones

  description = "A disk to be used for the Mounted Disk operational mode of Terraform Enterprise"
  labels      = var.labels
  type        = "pd-ssd"
  size        = 40
}

resource "google_compute_instance_template" "main" {
  name_prefix  = "${var.namespace}-tfe-template-"
  machine_type = var.machine_type

  disk {
    source_image = var.disk_source_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.disk_size
    disk_type    = var.disk_type
    labels       = var.labels
    mode         = "READ_WRITE"
    type         = "PERSISTENT"
  }

  dynamic "disk" {
    for_each = google_compute_region_disk.mounted_disk
    content {
      source = disk.value.name

      auto_delete = false
      boot        = false
      interface   = "SCSI"
      mode        = "READ_WRITE"
    }
  }

  network_interface {
    subnetwork = var.subnetwork
  }

  metadata_startup_script = var.metadata_startup_script

  service_account {
    scopes = ["cloud-platform"]

    email = var.service_account
  }

  labels = var.labels

  can_ip_forward       = true
  description          = "The instance template of the compute deployment for TFE."
  instance_description = "An instance of the compute deployment for TFE."

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "main" {
  name = "${var.namespace}-tfe-group-manager"

  base_instance_name = "${var.namespace}-tfe-vm"

  version {
    instance_template = google_compute_instance_template.main.self_link
  }

  distribution_policy_zones = local.zones
  target_size               = var.node_count

  dynamic "named_port" {
    for_each = local.named_ports
    content {
      name = named_port.value.name
      port = named_port.value.port
    }
  }

  dynamic "auto_healing_policies" {
    for_each = var.auto_healing_enabled ? ["one"] : []
    content {
      health_check      = google_compute_health_check.tfe_instance_health.self_link
      initial_delay_sec = 600
    }
  }
}

resource "google_compute_health_check" "tfe_instance_health" {
  name                = "${var.namespace}-tfe-health-check"
  check_interval_sec  = 60
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 6

  https_health_check {
    port         = 443
    request_path = "/_health_check"
  }
}
