# ------------------------------------------------------------------
# Subnet Group
# ------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-aurora-pg"
  description = "Subnet group for ${var.name_prefix} Aurora PostgreSQL cluster"
  subnet_ids  = var.subnet_ids

  tags = { Name = "${var.name_prefix}-aurora-pg-subnet-group" }
}

# ------------------------------------------------------------------
# Cluster Parameter Group
# ------------------------------------------------------------------
resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name_prefix}-aurora-pg16"
  family      = "aurora-postgresql16"
  description = "Aurora PostgreSQL 16 parameters for ${var.name_prefix}"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  # Reject any client connection that does not use TLS.
  # Enforces encryption in transit in addition to encryption at rest.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = { Name = "${var.name_prefix}-aurora-pg16-params" }
}

# ------------------------------------------------------------------
# Security Group
# ------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-aurora-pg-sg"
  description = "Aurora PostgreSQL — accept connections from EKS nodes only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-aurora-pg-sg" }
}

resource "aws_security_group_rule" "db_ingress_from_nodes" {
  description              = "Allow EKS nodes to connect to PostgreSQL"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = var.allowed_source_security_group_id
}

resource "aws_security_group_rule" "db_ingress_from_rotation_lambda" {
  description              = "Allow the rotation Lambda to connect to PostgreSQL"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.rotation_lambda.id
}

resource "aws_security_group_rule" "db_egress_all" {
  description       = "Allow all outbound from the DB cluster"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}

# ------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# manage_master_user_password delegates the master password lifecycle
# to Secrets Manager — AWS generates, stores, and rotates it on a
# configurable schedule using the RDS-managed rotation Lambda.
# No random_password or manual SM secret is needed.
# ------------------------------------------------------------------
resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.name_prefix}-aurora-pg"
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted               = true
  kms_key_id                      = var.kms_key_id
  backup_retention_period         = var.backup_retention_days
  preferred_backup_window         = "03:00-04:00"
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${var.name_prefix}-aurora-pg-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${var.name_prefix}-aurora-pg" }
}

# ------------------------------------------------------------------
# Configure rotation schedule on the AWS-managed master user secret.
# AWS uses its own internal RDS rotation Lambda — no Lambda ARN needed.
# Default AWS rotation interval is 7 days; this overrides that.
# ------------------------------------------------------------------
resource "aws_secretsmanager_secret_rotation" "master_password" {
  secret_id = aws_rds_cluster.this.master_user_secret[0].secret_arn

  rotation_rules {
    automatically_after_days = var.password_rotation_days
  }
}

# ------------------------------------------------------------------
# Aurora Instance — writer only (db.t3.medium is the smallest class)
# ------------------------------------------------------------------
resource "aws_rds_cluster_instance" "writer" {
  identifier                 = "${var.name_prefix}-aurora-pg-writer"
  cluster_identifier         = aws_rds_cluster.this.id
  instance_class             = var.instance_class
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  performance_insights_enabled = true

  tags = { Name = "${var.name_prefix}-aurora-pg-writer" }
}

# ------------------------------------------------------------------
# Reserved Instance (optional)
# ------------------------------------------------------------------
data "aws_rds_reserved_instance_offering" "this" {
  count = var.reserved_instance_enabled ? 1 : 0

  db_instance_class   = var.instance_class
  duration            = var.reserved_instance_term
  multi_az            = false
  offering_type       = var.reserved_instance_offering_type
  product_description = "aurora-postgresql"
}

resource "aws_rds_reserved_instance" "writer" {
  count = var.reserved_instance_enabled ? 1 : 0

  offering_id    = data.aws_rds_reserved_instance_offering.this[0].offering_id
  reservation_id = "${var.name_prefix}-aurora-pg-reservation"
  instance_count = 1
}

# ------------------------------------------------------------------
# Rotation Lambda Security Group
# (Lambda must reach Secrets Manager API and the DB)
# ------------------------------------------------------------------
resource "aws_security_group" "rotation_lambda" {
  name        = "${var.name_prefix}-db-rotation-lambda-sg"
  description = "Security group for the Aurora password rotation Lambda"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-db-rotation-lambda-sg" }
}

resource "aws_security_group_rule" "rotation_lambda_egress_https" {
  description       = "Allow rotation Lambda outbound HTTPS (Secrets Manager API)"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.rotation_lambda.id
}

resource "aws_security_group_rule" "rotation_lambda_egress_postgres" {
  description              = "Allow rotation Lambda to reach Aurora on 5432"
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rotation_lambda.id
  source_security_group_id = aws_security_group.db.id
}
