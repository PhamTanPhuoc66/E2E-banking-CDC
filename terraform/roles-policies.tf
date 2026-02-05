############## Kafka-S3############
# Tạo Role cho phép EC2(kafka) sử dụng (S3)
resource "aws_iam_role" "kafka_s3_role" {
  name = "kafka_s3_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Tạo chính sách (Policy) cho phép ghi vào Bucket cụ thể
resource "aws_iam_policy" "s3_write_policy" {
  name        = "s3_write_policy"
  description = "Allow writing to datalake bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject" 
        ]
        Resource = [
          aws_s3_bucket.datalake_bucket.arn,
          "${aws_s3_bucket.datalake_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Gắn chính sách vào Role
resource "aws_iam_role_policy_attachment" "attach_s3_write" {
  role       = aws_iam_role.kafka_s3_role.name
  policy_arn = aws_iam_policy.s3_write_policy.arn
}

# Tạo Instance Profile (cái để gắn Role vào EC2)
resource "aws_iam_instance_profile" "kafka_profile" {
  name = "kafka_profile"
  role = aws_iam_role.kafka_s3_role.name
}


######### SNOWFLAKE - S3 INTEGRATION #########

data "aws_caller_identity" "current" {}

locals {
  snowflake_role_name = "snowflake_s3_read_role"
  snowflake_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.snowflake_role_name}"
}
data "aws_iam_policy_document" "snowflake_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn]
    }

    # FIX: Dùng dynamic block để xử lý giá trị NULL
    # Logic: Chỉ tạo block "condition" này nếu storage_aws_external_id
    #        KHÔNG phải là null.
    dynamic "condition" {
      # for_each sẽ là một danh sách rỗng (0 phần tử) nếu ID là null
      # và là danh sách 1 phần tử nếu ID tồn tại.
      for_each = (
        snowflake_storage_integration.s3_integration.storage_aws_external_id == null
        ? [] 
        : [snowflake_storage_integration.s3_integration.storage_aws_external_id]
      )
      
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [condition.value] # Dùng giá trị từ for_each
      }
    }
  }
}
# 1. TẠO INTEGRATION (Dùng ARN giả lập)
resource "snowflake_storage_integration" "s3_integration" {
  name                 = "E2E_S3_INTEGRATION"
  storage_provider     = "S3"
  storage_aws_role_arn = local.snowflake_role_arn # ARN giả lập
  enabled              = true
  storage_allowed_locations = ["s3://${aws_s3_bucket.datalake_bucket.bucket}/"]
  
  depends_on = [
    aws_s3_bucket.datalake_bucket
  ]
}

# 2. TẠO IAM ROLE (Chờ Integration tạo xong để lấy ID thật)
resource "aws_iam_role" "snowflake_s3_role" {
  name = local.snowflake_role_name
  assume_role_policy = data.aws_iam_policy_document.snowflake_assume_role_policy.json

  # BẮT BUỘC ROLE CHỜ INTEGRATION HOÀN TẤT
  depends_on = [
    snowflake_storage_integration.s3_integration
  ]
}

# 3. GẮN CHÍNH SÁCH ĐỌC S3
resource "aws_iam_role_policy_attachment" "snowflake_s3_read" {
  role       = aws_iam_role.snowflake_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 
}