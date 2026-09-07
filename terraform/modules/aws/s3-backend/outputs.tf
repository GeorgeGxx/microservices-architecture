output "bucket_id" {
  description = "The name/ID of the S3 state bucket."
  value       = aws_s3_bucket.tf_state.id
}

output "bucket_arn" {
  description = "The ARN of the S3 state bucket."
  value       = aws_s3_bucket.tf_state.arn
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB state locking table."
  value       = aws_dynamodb_table.tf_lock.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB state locking table."
  value       = aws_dynamodb_table.tf_lock.arn
}
