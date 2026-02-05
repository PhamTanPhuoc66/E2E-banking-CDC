######### Tự động tạo Key Pair #########

# 1. Tạo private key trong bộ nhớ của Terraform (thuật toán RSA)
resource "tls_private_key" "generated" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Lưu private key xuống máy tính thành file "my-key-pair.pem"
# LƯU Ý: File này sẽ được tạo tại thư mục bạn chạy lệnh terraform apply
resource "local_file" "private_key_pem" {
  content         = tls_private_key.generated.private_key_pem
  filename        = "${path.module}/my-key-pair.pem"
  file_permission = "0400" # Đặt quyền chỉ đọc cho chủ sở hữu (bắt buộc để SSH hoạt động)
}

# 3. Upload public key lên AWS để EC2 sử dụng
resource "aws_key_pair" "generated" {
  key_name   = "terraform-generated-key"
  public_key = tls_private_key.generated.public_key_openssh
}