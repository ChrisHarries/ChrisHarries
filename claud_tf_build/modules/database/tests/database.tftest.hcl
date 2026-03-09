mock_provider "aws" {}
mock_provider "random" {}

variables {
  name_prefix                      = "test-dev"
  vpc_id                           = "vpc-12345678"
  subnet_ids                       = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_source_security_group_id = "sg-nodes"
  database_name                    = "app"
  master_username                  = "dbadmin"
  engine_version                   = "16.4"
  instance_class                   = "db.t3.medium"
  backup_retention_days            = 7
  deletion_protection              = false
  skip_final_snapshot              = true
  reserved_instance_enabled        = false
  reserved_instance_term           = 31536000
  reserved_instance_offering_type  = "No Upfront"
}

run "aurora_cluster_uses_postgresql_engine" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.engine == "aurora-postgresql"
    error_message = "Aurora cluster must use the aurora-postgresql engine"
  }
}

run "aurora_cluster_has_correct_identifier" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.cluster_identifier == "test-dev-aurora-pg"
    error_message = "Aurora cluster identifier must follow the <name_prefix>-aurora-pg convention"
  }
}

run "storage_encryption_is_enabled" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.storage_encrypted == true
    error_message = "Aurora cluster storage must be encrypted at rest"
  }
}

run "writer_instance_uses_correct_class" {
  command = plan

  assert {
    condition     = aws_rds_cluster_instance.writer.instance_class == var.instance_class
    error_message = "Writer instance class must match the input variable"
  }
}

run "writer_instance_is_not_publicly_accessible" {
  command = plan

  assert {
    condition     = aws_rds_cluster_instance.writer.publicly_accessible == false
    error_message = "Aurora writer instance must not be publicly accessible"
  }
}

run "security_group_allows_postgres_port_from_nodes" {
  command = plan

  assert {
    condition     = aws_security_group_rule.db_ingress_from_nodes.from_port == 5432
    error_message = "DB security group ingress must be on port 5432 (PostgreSQL)"
  }

  assert {
    condition     = aws_security_group_rule.db_ingress_from_nodes.source_security_group_id == var.allowed_source_security_group_id
    error_message = "DB ingress must be sourced from the node security group"
  }
}

run "subnet_group_uses_all_provided_subnets" {
  command = plan

  assert {
    condition     = length(aws_db_subnet_group.this.subnet_ids) == length(var.subnet_ids)
    error_message = "DB subnet group must include all provided subnet IDs"
  }
}

run "credentials_are_stored_in_secrets_manager" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.db_credentials.name == "test-dev/aurora-pg/credentials"
    error_message = "Secrets Manager secret must follow the <name_prefix>/aurora-pg/credentials naming convention"
  }
}

run "no_reserved_instance_when_disabled" {
  command = plan

  assert {
    condition     = length(aws_rds_reserved_instance.writer) == 0
    error_message = "No reserved instance should be created when reserved_instance_enabled is false"
  }
}

run "reserved_instance_term_validation_rejects_invalid_value" {
  command = plan

  variables {
    reserved_instance_term = 12345
  }

  expect_failures = [var.reserved_instance_term]
}
