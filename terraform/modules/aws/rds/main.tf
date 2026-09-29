locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-${var.environment}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = local.common_tags
}

resource "aws_security_group" "db" {
  name        = "${var.name}-${var.environment}-db-sg"
  description = "Allow Postgres access from application nodes"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-${var.environment}"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage      = var.allocated_storage
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.master_username
  password               = var.master_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  multi_az                  = var.multi_az
  deletion_protection       = var.deletion_protection
  backup_retention_period   = var.backup_retention_days
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.name}-${var.environment}-final" : null

  tags = local.common_tags

  lifecycle {
    # Protect production data both at the provider and Terraform graph layers.
    # This module only provisions managed cloud databases in staging/prod.
    # The literal is required by Terraform's lifecycle meta-argument rules.
    prevent_destroy = true

    precondition {
      condition     = var.environment != "prod" || var.backup_retention_days >= 7
      error_message = "Production RDS must retain automated backups for at least seven days."
    }

    precondition {
      condition     = var.environment != "prod" || var.deletion_protection
      error_message = "Production RDS requires deletion_protection to be enabled."
    }

    postcondition {
      condition     = self.storage_encrypted && self.backup_retention_period >= 7
      error_message = "RDS must remain encrypted and retain at least seven days of backups."
    }
  }
}
