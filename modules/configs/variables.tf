# === Required

variable "license_file" {
  type        = string
  description = "Path to license file for the application"
}

variable "cluster_api_endpoint" {
  type        = string
  description = "URI to the cluster api"
}

variable "common-config" {
  type = object({
    application_config = map(map(string)),
    ca_certs           = string,
  })
  description = "Configuration generated by the common config module"
}

variable "distribution" {
  type        = string
  description = "Type of linux distribution to use. (ubuntu or rhel)"
  default     = "ubuntu"
}

variable "airgap_package_url" {
  type        = string
  description = "URL of the Airgap package to install. This is a specific TFE release."
  default     = ""
}

variable "airgap_installer_url" {
  type        = string
  description = "URL of the Airgap installer package. This contains the base cluster software rather than a specific TFE release"
  default     = "https://install.terraform.io/installer/replicated-v5.tar.gz"
}

variable "primary_count" {
  type        = string
  description = "The count of primary instances being created."
  default     = "3"
}

variable "http_proxy_url" {
  type        = string
  description = "HTTP(S) Proxy URL"
  default     = ""
}

variable "installer_url" {
  type        = string
  description = "URL to the cluster installer tool"
  default     = "https://install.terraform.io/installer/ptfe-0.1.zip"
}

variable "import_key" {
  type        = string
  description = "An additional ssh pub key to import to all machines"
  default     = ""
}

variable "weave_cidr" {
  type        = string
  description = "custom weave CIDR range"
  default     = ""
}

variable "repl_cidr" {
  type        = string
  description = "custom replicated service CIDR range"
  default     = ""
}

variable "release_sequence" {
  type        = string
  description = "The sequence ID for the Terraform Enterprise version to pin the cluster to."
  default     = "latest"
}

# === Misc

resource "random_pet" "console_password" {
  length = 3
}

resource "random_string" "bootstrap_token_id" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "setup_token" {
  length  = 32
  upper   = false
  special = false
}

resource "random_string" "bootstrap_token_suffix" {
  length  = 16
  upper   = false
  special = false
}
