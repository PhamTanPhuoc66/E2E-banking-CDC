import requests
import json
import sys
import os
from dotenv import load_dotenv

# Tải các biến từ file .env
load_dotenv()

# URL của Kafka Connect REST API (vẫn dùng localhost vì qua SSH Tunnel)
CONNECT_URL = "http://localhost:8083/connectors"

# --- Lấy cấu hình nhạy cảm từ Biến Môi trường ---
RDS_ENDPOINT = os.getenv("CONNECT_RDS_ENDPOINT")
DB_USER = os.getenv("CONNECT_DB_USER")
DB_PASSWORD = os.getenv("CONNECT_DB_PASSWORD")
DB_NAME = os.getenv("CONNECT_DB_NAME")

# --- Kiểm tra xem các biến đã được load chưa ---
required_vars = {
    "CONNECT_RDS_ENDPOINT": RDS_ENDPOINT,
    "CONNECT_DB_USER": DB_USER,
    "CONNECT_DB_PASSWORD": DB_PASSWORD,
    "CONNECT_DB_NAME": DB_NAME
}

missing_vars = [key for key, value in required_vars.items() if not value or value == "<dán-endpoint-của-bạn-vào-đây>"]

if missing_vars:
    print(f"❌ LỖI: Các biến môi trường sau bị thiếu hoặc chưa được cập nhật trong file .env:")
    for var in missing_vars:
        print(f"  - {var}")
    sys.exit(1)


# --- Xây dựng config ---
connector_config = {
    "name": "aws-rds-mysql-connector",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        
        # Lấy từ .env
        "database.hostname": RDS_ENDPOINT,
        "database.port": "3306",
        "database.user": DB_USER, 
        "database.password": DB_PASSWORD, 
        "database.include.list": DB_NAME, 

        "database.server.id": "184054", # Đảm bảo ID này là duy nhất
        "database.server.name": "rds_mysql_server",
        
        # "kafka:9092" là ĐÚNG nếu Kafka và Connect chạy chung 1 Docker Compose
        "schema.history.internal.kafka.bootstrap.servers": "kafka:9092", 
        "schema.history.internal.kafka.topic": "schema-changes.mysql",
        "include.schema.changes": "true",
        "topic.prefix": "rds_mysql",
        "snapshot.mode": "initial",
        
        
        
        "decimal.handling.mode": "string",
        "snapshot.locking.mode": "none",
        # --- THÊM DÒNG NÀY ĐỂ SỬA LỖI MỚI ---
        "database.connection.properties": "allowPublicKeyRetrieval=true"
    }
}


# Gửi request POST để tạo connector
print(f"Attempting to create connector 'aws-rds-mysql-connector' at {CONNECT_URL}...")
try:
    response = requests.post(
        CONNECT_URL,
        headers={"Content-Type": "application/json"},
        data=json.dumps(connector_config)
    )

    if response.status_code == 201:
        print("✅ Connector created successfully!")
        print(json.dumps(response.json(), indent=2))
    elif response.status_code == 409:
        print("⚠️ Connector 'aws-rds-mysql-connector' already exists.")
    else:
        print(f"❌ Failed to create connector: {response.status_code}")
        print("--- Lỗi từ Kafka Connect ---")
        print(response.text)
        print("--------------------------")

except requests.exceptions.ConnectionError as e:
    print(f"\n❌ Lỗi kết nối: {e}")
    print("👉 KIỂM TRA: Bạn đã CHẠY SSH Tunnel chưa?")
except Exception as e:
    print(f"\n❌ Đã xảy ra lỗi không xác định: {e}")