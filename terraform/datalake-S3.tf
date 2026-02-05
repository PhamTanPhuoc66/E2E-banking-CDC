resource "aws_s3_bucket" "datalake_bucket" {
 
  bucket_prefix = "e2e-datalake-" 
  force_destroy = true # CẢNH BÁO: Cho phép xóa bucket ngay cả khi có dữ liệu (tiện cho môi trường dev/test)

  tags = {
    Name = "Datalake Bucket"
  }
}

# 1. Lấy thông tin region hiện tại từ provider
data "aws_region" "current" {}

# 2. Sử dụng biến region động trong service_name
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.e2e_vpc.id
  service_name = "com.amazonaws.${data.aws_region.current.id}.s3"

  tags = {
    Name = "s3-endpoint"
  }
}
