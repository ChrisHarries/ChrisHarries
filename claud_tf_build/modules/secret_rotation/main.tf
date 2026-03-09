data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ── Package the Lambda ────────────────────────────────────────────────────────

data "archive_file" "dd_key_rotation" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

# ── IAM ───────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "rotation_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation_lambda" {
  name               = "${var.name_prefix}-dd-rotation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.rotation_lambda_assume.json
}

data "aws_iam_policy_document" "rotation_lambda_policy" {
  statement {
    sid    = "SecretsManagerRotation"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]
    resources = [var.secret_arn]
  }

  statement {
    sid    = "VpcNetworking"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-dd-key-rotation:*",
    ]
  }
}

resource "aws_iam_role_policy" "rotation_lambda" {
  name   = "${var.name_prefix}-dd-rotation-lambda-policy"
  role   = aws_iam_role.rotation_lambda.id
  policy = data.aws_iam_policy_document.rotation_lambda_policy.json
}

# ── Security group ────────────────────────────────────────────────────────────

resource "aws_security_group" "rotation_lambda" {
  name        = "${var.name_prefix}-dd-rotation-lambda-sg"
  description = "Security group for the Datadog key rotation Lambda"
  vpc_id      = var.vpc_id

  egress {
    description      = "HTTPS outbound (IPv4) — Datadog API + Secrets Manager"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.name_prefix}-dd-rotation-lambda-sg"
  }
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "dd_key_rotation" {
  function_name    = "${var.name_prefix}-dd-key-rotation"
  description      = "Rotates the Datadog API key stored in Secrets Manager"
  role             = aws_iam_role.rotation_lambda.arn
  filename         = data.archive_file.dd_key_rotation.output_path
  source_code_hash = data.archive_file.dd_key_rotation.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.rotation_lambda.id]
  }

  environment {
    variables = {
      DD_SITE     = var.datadog_site
      DD_KEY_NAME = "${var.dd_key_name_prefix}-${var.name_prefix}"
    }
  }

  tags = {
    Name = "${var.name_prefix}-dd-key-rotation"
  }
}

# Allow Secrets Manager to invoke this Lambda
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dd_key_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = var.secret_arn
}

# ── Secret rotation schedule ──────────────────────────────────────────────────

resource "aws_secretsmanager_secret_rotation" "dd_api_key" {
  secret_id           = var.secret_arn
  rotation_lambda_arn = aws_lambda_function.dd_key_rotation.arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}
