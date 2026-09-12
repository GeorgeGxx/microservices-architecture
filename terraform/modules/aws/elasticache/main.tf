resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-${var.environment}-redis-sg-"
  description = "Security Group for ElastiCache Redis Cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis port from allowed security groups"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}-redis-sg"
      Environment = var.environment
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name}-${var.environment}-redis-subnet-group"
  description = "Subnet group for ElastiCache Redis cluster"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "${var.name}-${var.environment}-redis7-pg"
  family      = "redis7"
  description = "Custom Redis 7 parameter group for microservices caching"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-${var.environment}-redis"
  description          = "Redis replication group for ${var.name} (${var.environment})"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = 6379

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]
  parameter_group_name = aws_elasticache_parameter_group.this.name

  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true

  apply_immediately          = var.environment != "prod"
  auto_minor_version_upgrade = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}-redis"
      Environment = var.environment
    }
  )
}
