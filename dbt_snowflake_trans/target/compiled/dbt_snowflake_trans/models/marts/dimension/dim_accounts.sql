

WITH snapshot_source AS (
    SELECT * FROM E2E_DB.SNAPSHOTS.snp_accounts
)

SELECT
    account_id,
    customer_id,
    account_type,
    balance,
    currency,
    
    -- Business Logic vẫn giữ nguyên
    CASE 
        WHEN balance >= 5000 THEN 'VIP'
        WHEN balance >= 1000 THEN 'GOLD'
        ELSE 'STANDARD'
    END AS customer_segment,
    
    -- Cột lịch sử
    dbt_valid_from AS valid_from,
    dbt_valid_to   AS valid_to,
    
    last_updated_at,
    current_timestamp() AS dwh_load_at

FROM snapshot_source