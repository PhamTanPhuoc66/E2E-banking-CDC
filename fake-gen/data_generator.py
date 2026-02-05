import time
# Thay đổi thư viện psycopg2 thành mysql.connector
import mysql.connector
from decimal import Decimal, ROUND_DOWN
from faker import Faker
import random
import argparse
import sys
import os
from dotenv import load_dotenv

load_dotenv()

# -----------------------------
# Project configuration (safe to hardcode here)
# -----------------------------
NUM_CUSTOMERS = 10
ACCOUNTS_PER_CUSTOMER = 2
NUM_TRANSACTIONS = 50
MAX_TXN_AMOUNT = 1000.00
CURRENCY = "USD"

# Non-zero initial balances
INITIAL_BALANCE_MIN = Decimal("10.00")
INITIAL_BALANCE_MAX = Decimal("1000.00")

# Loop config
DEFAULT_LOOP = True
SLEEP_SECONDS = 2

# CLI override (run once mode)
parser = argparse.ArgumentParser(description="Run fake data generator")
parser.add_argument("--once", action="store_true", help="Run a single iteration and exit")
args = parser.parse_args()
LOOP = not args.once and DEFAULT_LOOP

# -----------------------------
# Helpers
# -----------------------------
fake = Faker()

def random_money(min_val: Decimal, max_val: Decimal) -> Decimal:
    val = Decimal(str(random.uniform(float(min_val), float(max_val))))
    return val.quantize(Decimal("0.01"), rounding=ROUND_DOWN)

# -----------------------------
# Connect to MySQL (thay vì MYSQL)
# -----------------------------
try:
    conn = mysql.connector.connect(
        host=os.getenv("MYSQL_HOST"),       # Giữ nguyên tên .env, nhưng đảm bảo giá trị là host MySQL
        port=os.getenv("MYSQL_PORT"),       # Giữ nguyên tên .env, nhưng đảm bảo giá trị là port MySQL
        database=os.getenv("MYSQL_DB"),     # Đổi 'dbname' thành 'database'
        user=os.getenv("MYSQL_USER"),       # Giữ nguyên tên .env, nhưng đảm bảo giá trị là user MySQL
        password=os.getenv("MYSQL_PASSWORD"), # Giữ nguyên tên .env, nhưng đảm bảo giá trị là pass MySQL
        autocommit=True                        # Đặt autocommit ở đây
    )
except mysql.connector.Error as err:
    print(f"Lỗi kết nối MySQL: {err}")
    sys.exit(1)

cur = conn.cursor()

# -----------------------------
# Core generation logic (one iteration)
# -----------------------------
def run_iteration():
    customers = []
    # 1. Generate customers
    for _ in range(NUM_CUSTOMERS):
        first_name = fake.first_name()
        last_name = fake.last_name()
        email = fake.unique.email()

        # THAY ĐỔI: Bỏ "RETURNING id" và dùng "cur.lastrowid"
        cur.execute(
            "INSERT INTO customers (first_name, last_name, email) VALUES (%s, %s, %s)",
            (first_name, last_name, email),
        )
        customer_id = cur.lastrowid # Lấy ID vừa chèn
        customers.append(customer_id)

    # 2. Generate accounts
    accounts = []
    for customer_id in customers:
        for _ in range(ACCOUNTS_PER_CUSTOMER):
            account_type = random.choice(["SAVINGS", "CHECKING"])
            initial_balance = random_money(INITIAL_BALANCE_MIN, INITIAL_BALANCE_MAX)
            
            # THAY ĐỔI: Bỏ "RETURNING id" và dùng "cur.lastrowid"
            cur.execute(
                "INSERT INTO accounts (customer_id, account_type, balance, currency) VALUES (%s, %s, %s, %s)",
                (customer_id, account_type, initial_balance, CURRENCY),
            )
            account_id = cur.lastrowid # Lấy ID vừa chèn
            accounts.append(account_id)

    # 3. Generate transactions (Không cần thay đổi vì không dùng RETURNING)
    txn_types = ["DEPOSIT", "WITHDRAWAL", "TRANSFER"]
    for _ in range(NUM_TRANSACTIONS):
        account_id = random.choice(accounts)
        txn_type = random.choice(txn_types)
        amount = round(random.uniform(1, MAX_TXN_AMOUNT), 2)
        related_account = None
        if txn_type == "TRANSFER" and len(accounts) > 1:
            related_account = random.choice([a for a in accounts if a != account_id])

        cur.execute(
            "INSERT INTO transactions (account_id, txn_type, amount, related_account_id, status) VALUES (%s, %s, %s, %s, 'COMPLETED')",
            (account_id, txn_type, amount, related_account),
        )

    print(f"✅ Generated {len(customers)} customers, {len(accounts)} accounts, {NUM_TRANSACTIONS} transactions.")

# -----------------------------
# Main loop
# -----------------------------
try:
    iteration = 0
    while True:
        iteration += 1
        print(f"\n--- Iteration {iteration} started ---")
        run_iteration()
        print(f"--- Iteration {iteration} finished ---")
        if not LOOP:
            break
        time.sleep(SLEEP_SECONDS)

except KeyboardInterrupt:
    print("\nInterrupted by user. Exiting gracefully...")

finally:
    cur.close()
    conn.close()
    print("MySQL connection closed.")
    sys.exit(0)