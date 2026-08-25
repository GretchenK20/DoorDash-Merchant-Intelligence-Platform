-- stg_synthetic_orders_dev.sql
-- Dev-only: reads from synthetic_orders seed instead of Delta Lake source.

{{ config(enabled=(target.name == 'dev')) }}

with source as (
    select * from {{ ref('synthetic_orders') }}
)

select
    order_id,
    business_id,
    dasher_id,
    cast(order_timestamp as timestamp)          as order_timestamp,
    cast(order_date as date)                    as order_date,
    date_trunc('month', cast(order_date as date)) as order_month,
    year(cast(order_date as date))              as order_year,
    cast(order_hour as integer)                 as order_hour,
    order_day_of_week,
    cast(estimated_delivery_min as integer)     as estimated_delivery_min,
    try_cast(actual_delivery_min as integer)    as actual_delivery_min,
    try_cast(delivery_delta_min as integer)     as delivery_delta_min,
    try_cast(is_on_time as boolean)             as is_on_time,
    cast(order_total_usd as double)             as order_total_usd,
    cast(delivery_fee_usd as double)            as delivery_fee_usd,
    order_status,
    true                                        as _is_synthetic

from source
where order_id is not null
