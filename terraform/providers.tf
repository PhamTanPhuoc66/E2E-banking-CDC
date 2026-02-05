terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.20.0"
    }
    snowflake = {
      source  = "snowflakedb/snowflake"
      
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2" 
    }
    dbtcloud = {
      source = "dbt-labs/dbtcloud"
      version = "~> 0.3" 
    }
  }
  
}

provider "aws" {
  region = "ap-southeast-2"
}

provider "snowflake" {
  organization_name = "qkdykkb"        
  account_name      = "uh49950"
  user = var.snowflake_user
  password = var.snowflake_password
  role     = var.snowflake_role
  preview_features_enabled = [
    "snowflake_storage_integration_resource",
    "snowflake_file_format_resource",
    "snowflake_stage_resource",
    "snowflake_table_resource",
    "snowflake_pipe_resource"
  ]
}
provider "dbtcloud" {
  account_id = var.dbt_account_id
  token      = var.dbt_token
  host_url = "https://dn358.us1.dbt.com/api"
}
