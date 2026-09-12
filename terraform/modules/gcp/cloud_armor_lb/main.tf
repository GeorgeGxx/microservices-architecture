# Cloud Armor Security Policy (WAF, DDoS & Rate Limiting)
resource "google_compute_security_policy" "this" {
  name        = "${var.name}-${var.environment}-security-policy"
  description = "Cloud Armor WAF policy for ${var.name} (${var.environment})"

  # Default allow rule
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # Rate limiting rule against DDoS and brute force
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_count
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate limit threshold to protect microservices"
  }
}

# Global Static IP
resource "google_compute_global_address" "this" {
  name        = "${var.name}-${var.environment}-lb-ip"
  description = "Global IP address for ${var.name} HTTPS Load Balancer"
}

# HTTP Health Check
resource "google_compute_health_check" "http" {
  name                = "${var.name}-${var.environment}-hc"
  check_interval_sec  = 15
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/actuator/health"
  }
}

# Global Backend Service
resource "google_compute_backend_service" "this" {
  name                  = "${var.name}-${var.environment}-backend-svc"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  enable_cdn            = false
  health_checks         = [google_compute_health_check.http.id]
  security_policy       = google_compute_security_policy.this.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# URL Map
resource "google_compute_url_map" "this" {
  name            = "${var.name}-${var.environment}-url-map"
  default_service = google_compute_backend_service.this.id
}

# Managed SSL Certificate (if domain is provided)
resource "google_compute_managed_ssl_certificate" "this" {
  count = var.domain_name != "" ? 1 : 0
  name  = "${var.name}-${var.environment}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }
}

# Target HTTPS Proxy (if domain is provided)
resource "google_compute_target_https_proxy" "this" {
  count            = var.domain_name != "" ? 1 : 0
  name             = "${var.name}-${var.environment}-https-proxy"
  url_map          = google_compute_url_map.this.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this[0].id]
}

# Target HTTP Proxy (for HTTP redirect / fallback)
resource "google_compute_target_http_proxy" "this" {
  name    = "${var.name}-${var.environment}-http-proxy"
  url_map = google_compute_url_map.this.id
}

# Global Forwarding Rule (HTTPS if domain provided, else HTTP)
resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.domain_name != "" ? 1 : 0
  name                  = "${var.name}-${var.environment}-https-fr"
  target                = google_compute_target_https_proxy.this[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.this.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name}-${var.environment}-http-fr"
  target                = google_compute_target_http_proxy.this.id
  port_range            = "80"
  ip_address            = google_compute_global_address.this.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
