data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "msk" {
  name_prefix = "${var.name}-${var.environment}-msk-sg-"
  description = "Security Group for Amazon MSK cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Kafka plaintext/TLS broker ports from EKS"
    from_port       = 9092
    to_port         = 9098
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "Allow outbound traffic only within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}-msk-sg"
      Environment = var.environment
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.name}-${var.environment}"
  retention_in_days = 14
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_msk_cluster" "this" {
  # MSK Provisioned currently supports Kafka 4.1.x; Kafka 4.2.x is Express-only.
  cluster_name           = "${var.name}-${var.environment}-kafka"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.client_subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.kms_key_arn

    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}-kafka"
      Environment = var.environment
    }
  )
}
