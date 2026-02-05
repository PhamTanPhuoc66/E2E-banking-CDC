
    
    

select
    email as unique_field,
    count(*) as n_records

from E2E_DB.RAW.stg_customers
where email is not null
group by email
having count(*) > 1


