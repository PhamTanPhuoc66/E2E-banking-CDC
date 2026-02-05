######### Kafka/Debezium Security Group #########   
resource "aws_security_group" "kafka_sg" {
  name        = "kafka_sg"
  description = "Security group for Kafka/Debezium host"
  vpc_id      = aws_vpc.e2e_vpc.id

  # 1. Cho phép SSH từ Bastion Host
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # 2. Cho phép truy cập Kafka (9092) từ trong VPC (cho các app sau này)
  ingress {
    description = "Kafka internal traffic"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  # 3. Cho phép truy cập Debezium API (8083) từ trong VPC
  ingress {
    description = "Debezium Connect API"
    from_port   = 8083
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Cần ra internet (qua NAT Gateway) để tải Docker images
  }

  tags = {
    Name = "kafka_sg"
  }
}


######### Kafka/Debezium Host Instance #########
resource "aws_instance" "kafka_host" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.kafka_instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.kafka_sg.id]
  key_name               = aws_key_pair.generated.key_name # Dùng chung key với Bastion
  root_block_device {
        volume_size = 15    # Dung lượng (GB)
        volume_type = "gp3" # Loại ổ cứng SSD mới, hiệu năng tốt hơn gp2
    }
  # Script tự động cài Docker khi khởi động
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              # Cài Docker Compose mới nhất
              curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              EOF
  iam_instance_profile = aws_iam_instance_profile.kafka_profile.name
  tags = {
    Name = "kafka_host"
  }
  ############################################# INIT####
  connection {
    type         = "ssh"
    user         = "ec2-user"
    private_key  = tls_private_key.generated.private_key_pem
    host         = self.private_ip # IP của Kafka Host
    
    # Cấu hình Bastion Jumpbox
    bastion_host        = aws_instance.bastion_host.public_ip
    bastion_user        = "ec2-user"
    bastion_private_key = tls_private_key.generated.private_key_pem
  }
  # 1. Upload file docker-compose.yml
  provisioner "file" {
    source      = "../kafka-debezium/docker-compose.yml" # Đường dẫn file trên máy bạn
    destination = "/home/ec2-user/docker-compose.yml"
  }

  # 2. Upload file consumer.py
  provisioner "file" {
    source      = "../kafka-debezium/consumer.py"
    destination = "/home/ec2-user/consumer.py"
  }

  # 3. Chạy lệnh cài đặt và khởi động (Thay thế các lệnh SSH thủ công)
  provisioner "remote-exec" {
    inline = [
      # 1. BẬT CHẾ ĐỘ DEBUG & GHI LOG (QUAN TRỌNG NHẤT)
      "set -e", # Gặp lỗi là dừng ngay
      "exec > >(tee /home/ec2-user/setup.log) 2>&1", # Ghi toàn bộ log ra file này

      "echo '🚀 Bắt đầu setup Kafka Host...'",

      # 2. WAIT LOGIC (Giữ nguyên của bạn)
      "echo '⏳ Đang chờ Docker Daemon...'",
      "until sudo systemctl is-active --quiet docker; do sleep 5; echo '...waiting for docker'; done",
      
      "echo '⏳ Đang chờ Docker Compose binary...'",
      "while [ ! -f /usr/local/bin/docker-compose ]; do sleep 5; echo '...waiting for binary'; done",

      # 3. CHẠY DOCKER COMPOSE (Có thêm bước Pull riêng để dễ debug)
      "cd /home/ec2-user",
      "echo '📥 Đang Pull Images (Bước này hay lỗi mạng nhất)...'",
      "sudo /usr/local/bin/docker-compose pull", # Tách lệnh pull ra để xem có lỗi mạng không

      "echo '🚀 Đang Up Containers...'",
      "sudo /usr/local/bin/docker-compose up -d",
      
      "echo 'zzz Chờ 15s cho Kafka ổn định...'",
      "sleep 15",

      # 4. KIỂM TRA SỐNG CÒN (Nếu docker ps rỗng thì báo lỗi ngay)
      "if [ -z \"$(sudo docker ps -q)\" ]; then echo '❌ LỖI: Docker Compose chạy xong nhưng không thấy container nào!'; exit 1; fi",
      "echo '✅ Docker Containers đang chạy:'",
      "sudo docker ps",

      # 5. CÀI PYTHON (Giữ nguyên)
      "echo '🐍 Setup Python Environment...'",
      "sudo dnf install python3-pip -y",
      "python3 -m venv /home/ec2-user/venv",
      "/home/ec2-user/venv/bin/pip install kafka-python boto3 pandas fastparquet",

      # 6. SYSTEMD SERVICE (Giữ nguyên)
      "echo '⚙️ Setup Systemd...'",
      "echo '[Unit]' > consumer.service",
      "echo 'Description=Kafka Consumer to S3' >> consumer.service",
      "echo 'After=network.target docker.service' >> consumer.service",
      
      "echo '[Service]' >> consumer.service",
      "echo 'User=ec2-user' >> consumer.service",
      "echo 'WorkingDirectory=/home/ec2-user' >> consumer.service",
      "echo 'Environment=PYTHONUNBUFFERED=1' >> consumer.service",
      "echo 'Environment=S3_BUCKET_NAME=${aws_s3_bucket.datalake_bucket.bucket}' >> consumer.service",
      
      "echo 'ExecStart=/home/ec2-user/venv/bin/python /home/ec2-user/consumer.py' >> consumer.service",
      "echo 'Restart=always' >> consumer.service",
      "echo 'RestartSec=10' >> consumer.service",
      
      "echo 'StandardOutput=append:/home/ec2-user/consumer.log' >> consumer.service",
      "echo 'StandardError=append:/home/ec2-user/consumer.error.log' >> consumer.service",
      
      "echo '[Install]' >> consumer.service",
      "echo 'WantedBy=multi-user.target' >> consumer.service",

      "sudo mv consumer.service /etc/systemd/system/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable consumer",
      "sudo systemctl restart consumer",
      
      "echo '🎉 SETUP HOÀN TẤT THÀNH CÔNG! 🎉'"
    ]
  }
}