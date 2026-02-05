######### SNOWFLAKE DWH RESOURCES #########

# Tạo Warehouse (cụm máy chủ ảo để chạy query)
resource "snowflake_warehouse" "dwh_wh" {
  name           = "E2E_WH"
  warehouse_size = "X-Small"
  auto_suspend   = 60 # Tự động tắt sau 60 giây không hoạt động
  auto_resume    = true
  comment        = "Warehouse chính cho dự án E2E"
}



#######INIT####
# ==========================================
# 1. DATABASE & SCHEMA & FILE FORMAT
# ==========================================

resource "snowflake_database" "e2e_db" {
  name = "E2E_DB"
}

resource "snowflake_schema" "raw" {
  database = snowflake_database.e2e_db.name
  name     = "RAW"
}

resource "snowflake_file_format" "parquet_format" {
  name        = "E2E_PARQUET_FORMAT"
  database    = snowflake_database.e2e_db.name
  schema      = snowflake_schema.raw.name
  format_type = "PARQUET"
  compression = "SNAPPY"
}

# ==========================================
# 2. STAGE (Trỏ vào root folder 'bank_data/')
# ==========================================

resource "snowflake_stage" "s3_stage" {
  name                = "E2E_S3_STAGE"
  database            = snowflake_database.e2e_db.name
  schema              = snowflake_schema.raw.name
  
  # URL trỏ đến folder gốc chứa dữ liệu
  url                 = "s3://${aws_s3_bucket.datalake_bucket.bucket}/bank_data/"
  
  storage_integration = snowflake_storage_integration.s3_integration.name
  file_format         = "FORMAT_NAME = ${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.E2E_PARQUET_FORMAT"
}

# ==========================================
# 3. TABLES (LANDING TABLES)
# ==========================================

# --- Table CUSTOMERS ---
resource "snowflake_table" "customers_landing" {
  database = snowflake_database.e2e_db.name
  schema   = snowflake_schema.raw.name
  name     = "CUSTOMERS_LANDING"

  column {
    name = "PAYLOAD"
    type = "VARIANT"
  }
  column {
    name = "LOAD_TIME"
    type = "TIMESTAMP_LTZ"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

# --- Table ACCOUNTS ---
resource "snowflake_table" "accounts_landing" {
  database = snowflake_database.e2e_db.name
  schema   = snowflake_schema.raw.name
  name     = "ACCOUNTS_LANDING"

  column {
    name = "PAYLOAD"
    type = "VARIANT"
  }
  column {
    name = "LOAD_TIME"
    type = "TIMESTAMP_LTZ"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

# --- Table TRANSACTIONS ---
resource "snowflake_table" "transactions_landing" {
  database = snowflake_database.e2e_db.name
  schema   = snowflake_schema.raw.name
  name     = "TRANSACTIONS_LANDING"

  column {
    name = "PAYLOAD"
    type = "VARIANT"
  }
  column {
    name = "LOAD_TIME"
    type = "TIMESTAMP_LTZ"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

# ==========================================
# 4. PIPES (Tự động ingest theo từng folder)
# ==========================================

# --- Pipe cho CUSTOMERS ---
resource "snowflake_pipe" "pipe_customers" {
  database    = snowflake_database.e2e_db.name
  schema      = snowflake_schema.raw.name
  name        = "PIPE_CUSTOMERS"
  auto_ingest = true
  
  # Logic: Lấy từ Stage gốc + folder con "customers/"
  copy_statement = <<EOT
    COPY INTO ${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.CUSTOMERS_LANDING (PAYLOAD)
    FROM (
      SELECT $1 
      FROM @${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.E2E_S3_STAGE/customers/
    )
  EOT
  
  depends_on = [snowflake_table.customers_landing,
    snowflake_stage.s3_stage,      
    snowflake_file_format.parquet_format]
}

# --- Pipe cho ACCOUNTS ---
resource "snowflake_pipe" "pipe_accounts" {
  database    = snowflake_database.e2e_db.name
  schema      = snowflake_schema.raw.name
  name        = "PIPE_ACCOUNTS"
  auto_ingest = true

  copy_statement = <<EOT
    COPY INTO ${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.ACCOUNTS_LANDING (PAYLOAD)
    FROM (
      SELECT $1 
      FROM @${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.E2E_S3_STAGE/accounts/
    )
  EOT

  depends_on = [snowflake_table.accounts_landing,
    snowflake_stage.s3_stage,      
    snowflake_file_format.parquet_format]
}

# --- Pipe cho TRANSACTIONS ---
resource "snowflake_pipe" "pipe_transactions" {
  database    = snowflake_database.e2e_db.name
  schema      = snowflake_schema.raw.name
  name        = "PIPE_TRANSACTIONS"
  auto_ingest = true

  copy_statement = <<EOT
    COPY INTO ${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.TRANSACTIONS_LANDING (PAYLOAD)
    FROM (
      SELECT $1 
      FROM @${snowflake_database.e2e_db.name}.${snowflake_schema.raw.name}.E2E_S3_STAGE/transactions/
    )
  EOT

  depends_on = [snowflake_table.transactions_landing,
    snowflake_stage.s3_stage,      
    snowflake_file_format.parquet_format]
}

# ==========================================
# 5. S3 NOTIFICATION (Kết nối "dây thần kinh")
# Phần này cực quan trọng: Báo cho SQS của Pipe biết khi có file mới
# ==========================================

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.datalake_bucket.id

  # 1. Trigger cho Customers
  queue {
    # Lấy ID của SQS Queue ẩn mà Snowflake tự tạo cho Pipe này
    queue_arn     = snowflake_pipe.pipe_customers.notification_channel
    events        = ["s3:ObjectCreated:*"]
    # Chỉ báo khi file nằm đúng đường dẫn này
    filter_prefix = "bank_data/customers/" 
    filter_suffix = ".parquet"
  }

  # 2. Trigger cho Accounts
  queue {
    queue_arn     = snowflake_pipe.pipe_accounts.notification_channel
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "bank_data/accounts/"
    filter_suffix = ".parquet"
  }

  # 3. Trigger cho Transactions
  queue {
    queue_arn     = snowflake_pipe.pipe_transactions.notification_channel
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "bank_data/transactions/"
    filter_suffix = ".parquet"
  }
  
  # Lưu ý: Cần đảm bảo Storage Integration đã được tạo xong trước khi Pipe chạy
  depends_on = [
    snowflake_pipe.pipe_customers,
    snowflake_pipe.pipe_accounts,
    snowflake_pipe.pipe_transactions
  ]
}

# =========================================================
# 0. TẠO WAREHOUSE CHO DBT (giúp tách riêng chi phí)
# =========================================================

resource "snowflake_warehouse" "dbt_wh" {
  name           = "DBT_WH"
  warehouse_size = "X-SMALL"
  auto_suspend   = 60
  auto_resume    = true
}