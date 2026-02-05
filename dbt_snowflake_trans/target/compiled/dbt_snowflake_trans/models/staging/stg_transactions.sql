

WITH source AS (
    SELECT * FROM E2E_DB.RAW.TRANSACTIONS_LANDING
),

parsed AS (
    SELECT
        PAYLOAD:id::INT AS transaction_id,
        PAYLOAD:account_id::INT AS account_id,
        PAYLOAD:txn_type::VARCHAR(20) AS txn_type,
        TRY_CAST(PAYLOAD:amount::VARCHAR AS DECIMAL(15, 2)) AS amount,
        PAYLOAD:related_account_id::INT AS related_account_id,
        PAYLOAD:status::VARCHAR(20) AS status,
        TRY_TO_TIMESTAMP(PAYLOAD:created_at::VARCHAR) AS created_at,
        
        -- Metadata
        PAYLOAD:__op::CHAR(1) AS dml_operation,
        TO_TIMESTAMP_NTZ(PAYLOAD:__source_ts_ms::NUMBER, 3) AS source_timestamp,
        LOAD_TIME
    FROM source
)

SELECT 
    transaction_id,
    account_id,
    txn_type,
    amount,
    related_account_id,
    status,
    created_at,
    source_timestamp as processed_at,
    current_timestamp() as staging_loaded_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id 
    ORDER BY source_timestamp DESC, LOAD_TIME DESC
) = 1
AND dml_operation != 'd'