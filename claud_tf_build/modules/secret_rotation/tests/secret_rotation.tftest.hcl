mock_provider "aws" {}
mock_provider "archive" {}

variables {
  name_prefix   = "test-dev"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-aaa", "subnet-bbb"]
  secret_arn    = "arn:aws:secretsmanager:eu-north-1:123456789012:secret:test-dev-dd-api-key-AbCdEf"
  rotation_days = 30
  datadog_site  = "datadoghq.eu"
}

run "lambda_function_has_correct_name" {
  command = plan

  assert {
    condition     = aws_lambda_function.dd_key_rotation.function_name == "test-dev-dd-key-rotation"
    error_message = "Lambda function name must follow the <name_prefix>-dd-key-rotation convention"
  }
}

run "lambda_uses_python312" {
  command = plan

  assert {
    condition     = aws_lambda_function.dd_key_rotation.runtime == "python3.12"
    error_message = "Lambda must use python3.12 runtime"
  }
}

run "lambda_has_correct_handler" {
  command = plan

  assert {
    condition     = aws_lambda_function.dd_key_rotation.handler == "handler.lambda_handler"
    error_message = "Lambda handler must be handler.lambda_handler"
  }
}

run "lambda_has_vpc_config" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.dd_key_rotation.vpc_config) > 0
    error_message = "Lambda must be deployed inside the VPC"
  }
}

run "lambda_env_has_dd_site" {
  command = plan

  assert {
    condition     = aws_lambda_function.dd_key_rotation.environment[0].variables["DD_SITE"] == "datadoghq.eu"
    error_message = "Lambda environment must include the DD_SITE variable set to datadoghq.eu"
  }
}

run "security_group_has_https_egress" {
  command = plan

  assert {
    condition     = aws_security_group.rotation_lambda.name == "test-dev-dd-rotation-lambda-sg"
    error_message = "Lambda security group name must follow naming convention"
  }
}

run "rotation_schedule_uses_correct_days" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret_rotation.dd_api_key.rotation_rules[0].automatically_after_days == var.rotation_days
    error_message = "Rotation schedule must match the rotation_days variable"
  }
}

run "lambda_permission_allows_secrets_manager" {
  command = plan

  assert {
    condition     = aws_lambda_permission.secrets_manager.principal == "secretsmanager.amazonaws.com"
    error_message = "Lambda permission principal must be secretsmanager.amazonaws.com"
  }
}
