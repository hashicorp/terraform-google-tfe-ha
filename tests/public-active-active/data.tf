data "tfe_outputs" "base" {
  organization = var.tfe_organization
  workspace    = var.tfe_workspace
}

data "google_compute_image" "ubuntu" {
  name = "ubuntu-2004-focal-v20210211"

  project = "ubuntu-os-cloud"
}