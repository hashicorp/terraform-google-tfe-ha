output "bucket" {
  value = google_service_account.bucket

  description = "The service account which will be used to access the storage bucket."
}

output "bucket_credentials" {
  value = base64decode(google_service_account_key.bucket.private_key)

  description = "The private key of the storage bucket service account."
}

output "primary" {
  value = google_service_account.primary

  description = "The service account to be attached to the primary VM instance template."
}