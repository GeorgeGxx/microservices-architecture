# AWS WAFv2 Web ACL at the CloudFront Edge (Layer 7 WAF Protection)
resource "aws_wafv2_web_acl" "edge" {
  name        = "${var.name}-${var.environment}-edge-waf"
  description = "CloudFront Edge WAF protecting S3 Frontend & EKS Istio ingress gateway NLB"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS Managed Rules: Common Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules: Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-waf-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting rule: Max 2000 requests per 5 minutes per IP
  rule {
    name     = "RateLimitPerIp"
    priority = 30

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-${var.environment}-waf-ratelimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-${var.environment}-edge-waf-summary"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# Origin Access Control (OAC) for secure S3 bucket access
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-${var.environment}-oac"
  description                       = "OAC for ${var.name} S3 Frontend Bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 Bucket Policy granting read access to CloudFront OAC only
resource "aws_s3_bucket_policy" "frontend_oac" {
  bucket = var.s3_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.s3_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

locals {
  s3_origin_id  = "S3FrontendOrigin"
  api_origin_id = "EksNlbApiOrigin"
}

# CloudFront Dual-Origin Distribution:
# 1. Origin 'S3FrontendOrigin': React 19 static files (index.html, *.js, *.css, assets)
# 2. Origin 'EksNlbApiOrigin': Dynamic backend (/api/* and /realms/*) -> AWS NLB -> Istio ingress gateway
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront Dual-Origin (S3 Frontend + EKS Istio NLB) - ${var.environment}"
  default_root_object = "index.html"
  price_class         = var.price_class
  aliases             = var.aliases
  web_acl_id          = aws_wafv2_web_acl.edge.arn

  # --- ORIGIN 1: S3 Static Frontend ---
  origin {
    domain_name              = var.s3_bucket_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # --- ORIGIN 2: AWS NLB Dynamic API & Keycloak ---
  origin {
    domain_name = var.api_origin_domain_name
    origin_id   = local.api_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # NLB Port 80
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default Behavior (/*): Serves React 19 SPA static assets from S3 with caching
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # Dynamic Behavior: /graphql* -> EKS NLB (Cosmo Router Federated Supergraph)
  ordered_cache_behavior {
    path_pattern     = "/graphql*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.api_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
  }

  # Dynamic Behavior: /api/* -> EKS NLB (No cache, all HTTP verbs, forward all headers)
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.api_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
  }

  # Dynamic Behavior: /realms/* (Keycloak OIDC) -> EKS NLB
  ordered_cache_behavior {
    path_pattern     = "/realms/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.api_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
  }

  # SPA Routing Support: Redirect 403 & 404 to /index.html with HTTP 200
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? "TLSv1.2_2021" : null
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}-cdn"
      Environment = var.environment
    }
  )
}
