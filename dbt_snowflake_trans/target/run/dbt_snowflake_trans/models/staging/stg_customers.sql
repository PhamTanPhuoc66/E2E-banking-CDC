
        

    
        create or replace dynamic table E2E_DB.RAW.stg_customers
    target_lag = '1 minute'
    warehouse = E2E_WH
    refresh_mode = AUTO

    initialize = ON_CREATE

    

    

    as (
        

WITH source AS (
    SELECT * FROM E2E_DB.RAW.CUSTOMERS_LANDING
),

parsed AS (
    SELECT
        PAYLOAD:id::INT AS customer_id,
        PAYLOAD:first_name::VARCHAR(50) AS first_name,
        PAYLOAD:last_name::VARCHAR(50) AS last_name,
        PAYLOAD:email::VARCHAR(100) AS email,
        
        -- Metadata
        PAYLOAD:__op::CHAR(1) AS dml_operation, 
        TO_TIMESTAMP_NTZ(PAYLOAD:__source_ts_ms::NUMBER, 3) AS source_timestamp,
        LOAD_TIME
    FROM source
)

SELECT 
    customer_id,
    first_name,
    last_name,
    email,
    source_timestamp as last_updated_at,
    current_timestamp() as staging_loaded_at -- Để biết DT chạy lúc nào
FROM parsed
-- Dùng QUALIFY để lọc dòng mới nhất ngay trong 1 câu lệnh (Gọn hơn CTE)
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id 
    ORDER BY source_timestamp DESC, LOAD_TIME DESC
) = 1
-- Logic: Lọc bỏ dòng Delete sau khi đã xếp hạng
AND dml_operation != 'd'
    )

    


    