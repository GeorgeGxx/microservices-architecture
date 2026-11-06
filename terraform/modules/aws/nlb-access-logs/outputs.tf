output "bucket_name" {
  description = "S3 bucket for Network Load Balancer access logs"
  value       = aws_s3_bucket.this.bucket
}

output "log_prefix" {
  description = "Prefix for Network Load Balancer access logs"
  value       = local.log_prefix
}
