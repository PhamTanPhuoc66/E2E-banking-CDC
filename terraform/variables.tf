variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr_block" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_cidr_block" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.2.0/24"
}



#############
variable "bastion_instance_type" {
  description = "Instance type for Bastion Host"
  type        = string
  default     = "t3.micro" # Đủ dùng cho Bastion và nằm trong Free Tier
}

variable "my_ip_cidr" {
  description = "Your IP address CIDR to allow SSH access to Bastion"
  type        = string
  default     = "0.0.0.0/0" # KHUYẾN NGHỊ: Thay bằng IP , ví dụ "1.2.3.4/32" để bảo mật hơn.
}

##############
variable "kafka_instance_type" {
  description = "Instance type for Kafka/Debezium Host"
  type        = string
  default     = "t3.small" # KHUYẾN NGHỊ: t3.small hoặc t3.medium
}

#######
variable "rds_db_name" {
  description = "Tên database ban đầu"
  type        = string
  default     = "inventory"
}

variable "rds_username" {
  description = "Username admin của RDS"
  type        = string
}

variable "rds_password" {
  description = "Password admin của RDS"
  type        = string
  sensitive   = true
}


############


variable "snowflake_user" {
  description = "Tên tài khoản admin của Snowflake (ví dụ: ADMIN_USER)"
  type        = string
  default = "PHAMTANPHUOC9009"
}

variable "snowflake_password" {
  description = "Mật khẩu cho tài khoản admin"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Role để Terraform sử dụng (ví dụ: ACCOUNTADMIN)"
  type        = string
  default     = "ACCOUNTADMIN"
}


######DBT CLOUD#
 #--- Biến cho dbt Cloud ---
variable "dbt_account_id" {
  description = "ID tài khoản dbt Cloud (Lấy trên URL)"
  type        = number
}

variable "dbt_token" {
  description = "Service Token API của dbt Cloud (User Settings -> API Access)"
  type        = string
  sensitive   = true
}

variable "dbt_project_name" {
  description = "Tên dự án trên dbt Cloud"
  type        = string
  default     = "E2E Bank Analytics"
}

variable "dbt_github_repo" {
  description = "Link SSH của Git Repo (git@github.com:...)"
  type        = string
}

# --- Biến cho Snowflake Connection (Dùng cho dbt kết nối vào) ---
variable "snowflake_dbt_password" {
  description = "Mật khẩu cho user service của dbt"
  type        = string
  sensitive   = true
}

variable "snowflake_org" {
  type = string
}

variable "snowflake_account" {
  type = string
}