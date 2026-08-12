locals {
  name = "${var.project}-${var.environment}"
  tags = merge(var.tags, { Component = "database" })
}

resource "random_password" "db" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.project}/${var.environment}/rds-credentials"
  description             = "RDS master credentials for ${local.name}"
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = "petclinic"
    password = random_password.db.result
  })
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.name}-db-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "DB subnet group for ${local.name}"
  tags        = merge(local.tags, { Name = "${local.name}-db-subnet-group" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${local.name}-mysql8-params"
  family      = "mysql8.0"
  description = "Custom parameter group for ${local.name}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = local.tags
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class
  db_name        = "petclinic"
  username       = "petclinic"
  password       = random_password.db.result
  port           = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  skip_final_snapshot   = var.skip_final_snapshot
  deletion_protection   = var.deletion_protection
  copy_tags_to_snapshot = true
  apply_immediately     = true

  tags       = merge(local.tags, { Name = "${local.name}-mysql" })
  depends_on = [aws_secretsmanager_secret_version.rds]
}
