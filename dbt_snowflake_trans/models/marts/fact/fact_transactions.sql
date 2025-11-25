{{ config(
    materialized='incremental',
    unique_key='transaction_id',
    incremental_strategy='delete+insert' 
) }}

WITH transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
    
    -- LOGIC INCREMENTAL:
    -- Chỉ lấy các giao dịch có thời gian xử lý (processed_at) LỚN HƠN 
    -- thời gian max hiện có trong bảng đích (this).
    {% if is_incremental() %}
    WHERE processed_at > (SELECT MAX(processed_at) FROM {{ this }})
    {% endif %}
),

-- Join thêm thông tin Account để lấy Customer ID (Denormalization)
accounts AS (
    SELECT account_id, customer_id FROM {{ ref('stg_accounts') }}
)

SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id, 
    
    t.txn_type,
    t.status,
    t.amount,
    
    -- Tách Date Dimension (Ngày/Tháng/Năm) phục vụ Partitioning hoặc Filter nhanh
    DATE(t.created_at) AS transaction_date_key,
    YEAR(t.created_at) AS transaction_year,
    MONTH(t.created_at) AS transaction_month,
    
    t.created_at AS transaction_timestamp,
    t.processed_at, -- Cột mốc để chạy incremental
    current_timestamp() AS dwh_load_at

FROM transactions t
LEFT JOIN accounts a ON t.account_id = a.account_id