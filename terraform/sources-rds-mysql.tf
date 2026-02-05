resource "aws_security_group" "rds_source_sg" {
  name        = "rds_source_sg"
  description = "Allow access from Debezium"
  vpc_id      = aws_vpc.e2e_vpc.id

  # Cho phép EC2 Kafka (nơi chạy Debezium) kết nối vào MySQL (port 3306)
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka_sg.id]
  }
  
  # (Tùy chọn) Cho phép Bastion kết nối để bạn tạo bảng, insert dữ liệu test
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  tags = {
    Name = "rds_source_sg"
  }
}


data "aws_availability_zones" "available" {
  state = "available"
}

# Tạo subnet thứ 2 cho RDS MySQL (để đảm bảo 2 AZ khác nhau)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.e2e_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private_subnet_2_rds"
  }
}


resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-source-subnet-group"
  # Cần ít nhất 2 subnet ở 2 AZ khác nhau
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "RDS Source Subnet Group"
  }
}

resource "aws_db_instance" "source_db" {
  identifier             = "source-mysql-db"
  engine                 = "mysql"
  engine_version         = "8.0"        
  instance_class         = "db.t3.micro" 
  allocated_storage      = 10           
  db_name                = var.rds_db_name
  username               = var.rds_username
  password               = var.rds_password 
  
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_source_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false         # Đặt trong private subnet

  # CẤU HÌNH QUAN TRỌNG CHO CDC (DEBEZIUM):
  backup_retention_period = 1            # Phải > 0 để bật binlog
  parameter_group_name    = aws_db_parameter_group.rds_cdc_params.name
  apply_immediately = true
}

# TẠO PARAMETER GROUP TÙY CHỈNH CHO DEBEZIUM
resource "aws_db_parameter_group" "rds_cdc_params" {
  name   = "e2e-mysql8-cdc-params"
  family = "mysql8.0" # Phải khớp với engine và version
  description = "Parameter group for Debezium (enables binlog_format=ROW)"

  # Đây là cài đặt quan trọng nhất
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  tags = {
    Name = "e2e-mysql8-cdc-params"
  }
}

