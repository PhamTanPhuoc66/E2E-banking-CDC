resource "null_resource" "init_rds" {
  depends_on = [aws_db_instance.source_db, aws_instance.bastion_host]

  # Kết nối vào Bastion
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.generated.private_key_pem
    host        = aws_instance.bastion_host.public_ip
  }

  # Upload file SQL lên Bastion
  provisioner "file" {
    source      = "../fake-gen/rds_db_creation.sql"
    destination = "/home/ec2-user/rds_db_creation.sql"
  }

  # Cài MySQL Client trên Bastion và chạy lệnh
  provisioner "remote-exec" {
    inline = [
      # 1. Cập nhật package
      "sudo dnf update -y",
      
      # 2. Cài đặt MySQL Client (Trên Amazon Linux 2023 dùng mariadb105)
      "sudo dnf install mariadb105 -y",
      
      # 3. Chờ một chút cho chắc ăn
      "sleep 5",
      
      # 4. Chạy lệnh SQL
      "mysql -h ${aws_db_instance.source_db.address} -u ${var.rds_username} -p'${var.rds_password}' < /home/ec2-user/rds_db_creation.sql"
    ]
  }
}