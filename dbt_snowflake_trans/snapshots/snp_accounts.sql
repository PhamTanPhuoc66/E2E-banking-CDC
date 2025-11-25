{% snapshot snp_accounts %}

{{
    config(
      target_database='E2E_DB',
      target_schema='SNAPSHOTS',
      unique_key='account_id',

      strategy='timestamp',
      updated_at='last_updated_at',
    )
}}

SELECT * FROM {{ ref('stg_accounts') }}

{% endsnapshot %}