import json
import time
import io
import os
import sys
from kafka import KafkaConsumer
import pandas as pd
import boto3

# --- Cấu hình ---

# 1. KAFKA SERVER: (Kết nối với cổng 29092 của host)
#    (Giữ nguyên, localhost:29092 là đúng)
KAFKA_BROKER = 'localhost:29092' 

# 2. TOPIC PATTERN: (Giữ nguyên, nó sẽ bắt cả 3 bảng)
TOPIC_PATTERN = '^rds_mysql\\.bankdb\\..+'

# 3. S3 & BATCHING:
S3_BUCKET_NAME = os.getenv('S3_BUCKET_NAME')
BATCH_SIZE = 100
BATCH_TIMEOUT_SECONDS = 60

# --- DANH SÁCH CÁC BẢNG CẦN XỬ LÝ ---
# (Thêm tên bảng vào đây nếu bạn có bảng mới)
TABLES_TO_PROCESS = ["customers", "accounts", "transactions"]

# Khởi tạo S3 client
try:
    s3_client = boto3.client('s3')
    print(f"✅ Boto3 client initialized. Sẽ upload lên bucket: {S3_BUCKET_NAME}")
    print("Đang chờ xác thực IAM Role...")
    s3_client.list_objects_v2(Bucket=S3_BUCKET_NAME, MaxKeys=1)
    print("✅ IAM Role authenticated successfully.")
except Exception as e:
    print(f"❌ Lỗi khi khởi tạo Boto3 S3 client: {e}")
    exit(1)


def upload_to_s3(batch_data, table_name):
    """
    Chuyển đổi danh sách message (dict) của MỘT BẢNG thành DataFrame,
    lưu dưới dạng Parquet và upload lên S3.
    """
    if not batch_data:
        print(f"Batch cho bảng '{table_name}' rỗng, bỏ qua upload.")
        return

    print(f"Đang xử lý {len(batch_data)} message cho bảng: {table_name}...")

    try:
        # Chỉ lấy phần payload 'after'
        processed_data = []
        for msg in batch_data:
            payload = msg.get('payload', {})
            after_data = payload.get('after')
            
            if after_data:
                # Thêm thông tin meta
                after_data['__op'] = payload.get('op') # 'c', 'u', 'd'
                after_data['__source_ts_ms'] = payload.get('ts_ms') # Thời gian event ở DB
                processed_data.append(after_data)
            
            # Xử lý DELETE (tombstone)
            elif payload.get('op') == 'd':
                before_data = payload.get('before')
                if before_data:
                    before_data['__op'] = 'd' # Đánh dấu là delete
                    before_data['__source_ts_ms'] = payload.get('ts_ms')
                    processed_data.append(before_data)

        if not processed_data:
            print(f"Không có data 'after' hoặc 'before' (delete) trong batch {table_name}, bỏ qua.")
            return
            
        df = pd.DataFrame(processed_data)
        
        # Đặt tên file động VÀ PHÂN VÙNG THEO TÊN BẢNG
        file_timestamp = int(time.time())
        s3_key = f"bank_data/{table_name}/debezium_batch_{file_timestamp}.parquet"
        
        out_buffer = io.BytesIO()
        df.to_parquet(out_buffer, index=False, engine='fastparquet')
        out_buffer.seek(0)
        
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=out_buffer.getvalue()
        )
        print(f"✅ Upload thành công {len(processed_data)} records (bảng {table_name}) lên S3: s3://{S3_BUCKET_NAME}/{s3_key}")

    except Exception as e:
        print(f"❌ Lỗi khi upload batch cho bảng {table_name}: {e}")


# --- Main ---
print(f"Connecting to Kafka broker at {KAFKA_BROKER}...")

try:
    consumer = KafkaConsumer(
        bootstrap_servers=KAFKA_BROKER,
        auto_offset_reset='earliest',
        value_deserializer=lambda v: json.loads(v.decode('utf-8')),
        group_id='my-s3-parquet-uploader-group-v2', # Đổi group_id để bắt đầu lại từ đầu
        consumer_timeout_ms=1000
    )
except Exception as e:
    print(f"❌ Lỗi khi kết nối tới Kafka: {e}")
    exit(1)

consumer.subscribe(pattern=TOPIC_PATTERN)
print("\n✅ Consumer connected. Listening for messages...")
print(f"(Sẽ upload mỗi {BATCH_SIZE} message/bảng hoặc mỗi {BATCH_TIMEOUT_SECONDS} giây)")
print("(Press Ctrl+C to stop listening)\n")

# --- THAY ĐỔI LOGIC BATCH ---
# Tạo một dictionary để chứa batch cho TỪNG BẢNG
batches = {table: [] for table in TABLES_TO_PROCESS}
last_upload_times = {table: time.time() for table in TABLES_TO_PROCESS}

try:
    while True:
        # Lấy message
        for topic_partition, messages in consumer.poll(timeout_ms=1000).items():
            for msg in messages:
                if not msg.value:
                    continue # Bỏ qua tombstones
                
                try:
                    # Tách tên bảng từ topic: 'rds_mysql.bankdb.customers' -> 'customers'
                    topic_parts = msg.topic.split('.')
                    if len(topic_parts) < 3:
                        continue # Bỏ qua topic không đúng định dạng (vd: schema-changes.mysql)
                    
                    table_name = topic_parts[-1]

                    # Nếu bảng này là bảng chúng ta quan tâm, thêm vào batch tương ứng
                    if table_name in batches:
                        batches[table_name].append(msg.value)
                    else:
                        # In ra cảnh báo nếu thấy topic lạ (chỉ in 1 lần)
                        if table_name not in TABLES_TO_PROCESS:
                            print(f"⚠️ Thấy topic mới, nhưng không xử lý: {msg.topic}")
                            TABLES_TO_PROCESS.append(table_name) # Thêm vào để không in lại
                            batches[table_name] = []
                            last_upload_times[table_name] = time.time()

                except Exception as e:
                    print(f"Lỗi xử lý message: {e}")

        # Kiểm tra điều kiện batch CHO TỪNG BẢNG
        current_time = time.time()
        for table_name in list(batches.keys()):
            batch_data = batches[table_name]
            last_upload = last_upload_times[table_name]

            if (len(batch_data) >= BATCH_SIZE) or \
               (current_time - last_upload >= BATCH_TIMEOUT_SECONDS and len(batch_data) > 0):
                
                upload_to_s3(batch_data, table_name)
                
                # Reset batch VÀ thời gian cho BẢNG ĐÓ
                batches[table_name] = []
                last_upload_times[table_name] = current_time

except KeyboardInterrupt:
    print("\n🛑 Interrupted by user. Uploading all final batches...")
    # Cố gắng upload batch cuối cùng của TẤT CẢ các bảng
    for table_name, batch_data in batches.items():
        if len(batch_data) > 0:
            upload_to_s3(batch_data, table_name)
finally:
    print("Closing consumer.")
    consumer.close()