resource "google_sql_database_instance" "this" {
  name             = "${var.name}-${var.environment}-pg16"
  database_version = "POSTGRES_16"
  region           = var.region

  depends_on = [var.vpc_peering_dependency]

  settings {
    tier              = var.tier
    availability_type = var.high_availability ? "REGIONAL" : "ZONAL"
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.high_availability
      start_time                     = "03:00"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
    }
  }

  deletion_protection = var.deletion_protection
}

resource "google_sql_database" "databases" {
  for_each = toset(var.database_names)

  name     = each.key
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "this" {
  name     = var.db_username
  instance = google_sql_database_instance.this.name
  password = var.db_password
}
