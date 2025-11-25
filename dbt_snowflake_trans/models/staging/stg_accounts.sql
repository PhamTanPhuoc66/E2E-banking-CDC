{{ config(
    materialized = 'dynamic_table',
    snowflake_warehouse = 'E2E_WH',
    target_lag = '1 minute',
    on_configuration_change = 'apply'
) }}

WITH source AS (
    SELECT * FROM {{ source('e2e_raw', 'ACCOUNTS_LANDING') }}
),

parsed AS (
    SELECT
        PAYLOAD:id::INT AS account_id,
        PAYLOAD:customer_id::INT AS customer_id,
        PAYLOAD:account_type::VARCHAR(20) AS account_type,
        TRY_CAST(PAYLOAD:balance::VARCHAR AS DECIMAL(15, 2)) AS balance,
        PAYLOAD:currency::VARCHAR(3) AS currency,
        
        -- Metadata
        PAYLOAD:__op::CHAR(1) AS dml_operation,
        TO_TIMESTAMP_NTZ(PAYLOAD:__source_ts_ms::NUMBER, 3) AS source_timestamp,
        LOAD_TIME
    FROM source
)

SELECT 
    account_id,
    customer_id,
    account_type,
    balance,
    currency,
    source_timestamp as last_updated_at,
    current_timestamp() as staging_loaded_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY account_id 
    ORDER BY source_timestamp DESC, LOAD_TIME DESC
) = 1
AND dml_operation != 'd'