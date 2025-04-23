terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.11.4"
}

provider "aws" {
  region = "us-east-1"
}

# Random ID for Unique Resource Names

resource "random_id" "suffix" {
  byte_length = 8
}

# S3 Buckets

resource "aws_s3_bucket" "source_bucket" {
  bucket = "image-upload-source-bucket-${random_id.suffix.hex}" # Unique bucket name

  tags = {
    Name        = "Image Upload Source Bucket"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source_sse" {
  bucket = aws_s3_bucket.source_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "source_bucket_policy" {
  bucket = aws_s3_bucket.source_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject"
        ],
        Effect = "Allow",
        Principal = {
          AWS = [aws_iam_role.lambda_execution_role.arn]
        },
        Resource = "${aws_s3_bucket.source_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket" "processed_bucket" {
  bucket = "processed-image-destination-bucket-${random_id.suffix.hex}" # Unique bucket name

  tags = {
    Name        = "Processed Image Destination Bucket"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_sse" {
  bucket = aws_s3_bucket.processed_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role and Policy for Lambda Execution

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-image-processor-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "Lambda Execution Role for Image Processor"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "lambda_execution_policy" {
  name        = "lambda-image-processor-policy-${random_id.suffix.hex}"
  description = "IAM policy for Lambda to access S3 and CloudWatch Logs"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject"
        ],
        Effect = "Allow",
        Resource = "${aws_s3_bucket.source_bucket.arn}/*"
      },
      {
        Action = [
          "s3:PutObject"
        ],
        Effect = "Allow",
        Resource = "${aws_s3_bucket.processed_bucket.arn}/*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

resource "aws_lambda_function" "image_processor_lambda" {
  function_name    = "image-processor-lambda-${random_id.suffix.hex}"
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  filename         = "./lambda_image_processor/lambda.zip"
  source_code_hash = filebase64sha256("./lambda_image_processor/lambda.zip")
  role             = aws_iam_role.lambda_execution_role.arn
  memory_size      = 256
  timeout          = 30

  environment {
    variables = {
      PROCESSED_BUCKET_NAME = aws_s3_bucket.processed_bucket.bucket
    }
  }

  tracing_config {
    mode = "Active" # Enable X-Ray tracing
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_execution_policy_attachment]

  tags = {
    Name        = "Image Processor Lambda"
    Environment = "dev"
  }
}

# S3 Event Trigger for Lambda

resource "aws_s3_bucket_notification" "image_upload_trigger" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor_lambda.arn
    events       = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/" # Optional: Trigger only for objects in the 'uploads/' prefix
  }

  depends_on = [aws_lambda_function.image_processor_lambda]
}

# Allow S3 to invoke the Lambda function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
  source_account = data.aws_caller_identity.current.account_id

  depends_on = [aws_s3_bucket_notification.image_upload_trigger]
}

# Data Sources

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
