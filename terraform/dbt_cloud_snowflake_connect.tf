
# =========================================================
# 1. SETUP USER & QUYỀN TRONG SNOWFLAKE (Fix Version 1.0)
# =========================================================

# 1.1. Tạo Account Role
resource "snowflake_account_role" "dbt_role" {
  name = "DBT_ROLE"
}

# 1.2. Tạo User service cho dbt
resource "snowflake_user" "dbt_user" {
  name              = "DBT_SERVICE_USER"
  password          = var.snowflake_dbt_password
  default_role      = snowflake_account_role.dbt_role.name
  default_warehouse = snowflake_warehouse.dbt_wh.name
}

# 1.3. Cấp quyền WAREHOUSE
resource "snowflake_grant_privileges_to_account_role" "dbt_wh_usage" {
  account_role_name = snowflake_account_role.dbt_role.name 
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.dbt_wh.name
  }
}

# 1.4. Cấp quyền DATABASE
resource "snowflake_grant_privileges_to_account_role" "dbt_db_usage" {
  account_role_name = snowflake_account_role.dbt_role.name 
  privileges        = ["USAGE", "CREATE SCHEMA"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.e2e_db.name
  }
}

# 1.5. Cấp quyền SCHEMA (Chỉ USAGE)
resource "snowflake_grant_privileges_to_account_role" "dbt_raw_usage" {
  account_role_name = snowflake_account_role.dbt_role.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.e2e_db.name}\".\"${snowflake_schema.raw.name}\""
  }
}

# 1.6. Cấp quyền SELECT cho các bảng ĐANG CÓ (Current Tables)
# --- QUAN TRỌNG: Dùng depends_on để fix lỗi 'Object does not exist' ---
resource "snowflake_grant_privileges_to_account_role" "dbt_raw_select_current" {
  account_role_name = snowflake_account_role.dbt_role.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema           = "\"${snowflake_database.e2e_db.name}\".\"${snowflake_schema.raw.name}\""
    }
  }
  
  # Bắt buộc phải chờ 3 bảng này tạo xong thì mới cấp quyền được
  depends_on = [
    snowflake_table.customers_landing,
    snowflake_table.accounts_landing,
    snowflake_table.transactions_landing
  ]
}

# 1.7. Cấp quyền SELECT cho các bảng TƯƠNG LAI (Future Tables)
resource "snowflake_grant_privileges_to_account_role" "dbt_raw_select_future" {
  account_role_name = snowflake_account_role.dbt_role.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema           = "\"${snowflake_database.e2e_db.name}\".\"${snowflake_schema.raw.name}\""
    }
  }
}

# 1.8. Gán Role cho User
resource "snowflake_grant_account_role" "dbt_user_grant" {
  role_name = snowflake_account_role.dbt_role.name
  user_name = snowflake_user.dbt_user.name
}


# =========================================================
# 2. SETUP DBT CLOUD PROJECT & CONNECTION
# =========================================================

# Tạo Project
resource "dbtcloud_project" "e2e_project" {
  name = var.dbt_project_name
  # Sửa lại: Bỏ dấu gạch chéo ở đầu
  dbt_project_subdirectory = "dbt_snowflake_trans"
}

# Kết nối Git
resource "dbtcloud_repository" "github_repo" {
  project_id         = dbtcloud_project.e2e_project.id
  remote_url         = var.dbt_github_repo
  git_clone_strategy = "deploy_key"
}

resource "dbtcloud_project_repository" "link_repo" {
  project_id    = dbtcloud_project.e2e_project.id
  repository_id = dbtcloud_repository.github_repo.repository_id
}

# Kết nối Snowflake
resource "dbtcloud_connection" "snowflake_conn" {
  project_id = dbtcloud_project.e2e_project.id
  name       = "Snowflake Connection"
  type       = "snowflake"
  
  account   = "${var.snowflake_org}-${var.snowflake_account}" 
  database  = snowflake_database.e2e_db.name
  warehouse = snowflake_warehouse.dbt_wh.name
  role      = snowflake_account_role.dbt_role.name
  
  allow_sso        = false
  allow_keep_alive = false
}

# Môi trường chạy
resource "dbtcloud_environment" "prod_env" {
  project_id    = dbtcloud_project.e2e_project.id
  name          = "Production"
  dbt_version   = "latest"
  type          = "deployment"
  
  # Cấu hình Branch
  use_custom_branch = true 
  custom_branch     = "dbt_cloud"

  # Gắn Credential và Connection
  credential_id = dbtcloud_snowflake_credential.prod_cred.credential_id
  connection_id = dbtcloud_connection.snowflake_conn.connection_id
}

# Credential
resource "dbtcloud_snowflake_credential" "prod_cred" {
  project_id  = dbtcloud_project.e2e_project.id
  auth_type   = "password"
  num_threads = 4
  
  user        = snowflake_user.dbt_user.name
  password    = var.snowflake_dbt_password 
  schema      = "ANALYTICS"
}

# Job chạy mỗi 5 phút
resource "dbtcloud_job" "five_minute_job" {
  project_id        = dbtcloud_project.e2e_project.id
  environment_id    = dbtcloud_environment.prod_env.environment_id
  name              = "5 Minute Data Build"
  execute_steps     = ["dbt build"]
  
  triggers = {
    github_webhook       = false
    git_provider_webhook = false
    schedule             = true
    custom_branch_only   = true
  }

  schedule_type = "custom_cron"
  schedule_cron = "*/5 * * * *" 
}