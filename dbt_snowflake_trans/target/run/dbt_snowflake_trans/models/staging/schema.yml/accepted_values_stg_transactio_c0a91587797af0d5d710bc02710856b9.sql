
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        txn_type as value_field,
        count(*) as n_records

    from E2E_DB.RAW.stg_transactions
    group by txn_type

)

select *
from all_values
where value_field not in (
    'DEPOSIT','WITHDRAWAL','TRANSFER'
)



  
  
      
    ) dbt_internal_test