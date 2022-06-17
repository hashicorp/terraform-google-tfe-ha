provider "google" {
  credentials = local.google.credentials
  project     = local.google.project
  region      = local.google.region
  zone        = local.google.zone
}

provider "google-beta" {
  credentials = local.google.credentials
  project     = local.google.project
  region      = local.google.region
  zone        = local.google.zone
}

provider "tfe" {
  hostname = try(var.tfe.hostname, local.tfe.hostname)
  token    = try(var.tfe.token, local.tfe.token)
}