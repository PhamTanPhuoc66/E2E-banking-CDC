{{ config(
    materialized='table',
    unique_key='customer_id'
) }}

WITH snapshot_source AS (
    -- Đọc từ bảng Snapshot thay vì Staging
    SELECT * FROM {{ ref('snp_customers') }}
)

SELECT
    customer_id,
    CONCAT(first_name, ' ', last_name) AS full_name,
    first_name,
    last_name,
    email,
    
    -- Các cột của Snapshot
    dbt_valid_from AS valid_from,
    dbt_valid_to   AS valid_to,
    
    last_updated_at,
    current_timestamp() AS dwh_load_at

FROM snapshot_source
