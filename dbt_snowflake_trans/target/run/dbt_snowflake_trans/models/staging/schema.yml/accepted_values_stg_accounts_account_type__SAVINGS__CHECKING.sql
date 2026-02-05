
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        account_type as value_field,
        count(*) as n_records

    from E2E_DB.RAW.stg_accounts
    group by account_type

)

select *
from all_values
where value_field not in (
    'SAVINGS','CHECKING'
)



  
  
      
    ) dbt_internal_test