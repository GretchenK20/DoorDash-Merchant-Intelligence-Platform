-- stg_synthetic_orders.sql
-- Synthetic order events — clearly labeled throughout
-- Adds delivery operations dimension absent from static Yelp data

{{ config(enabled=(target.name != 'dev')) }}

with source as (
    select * from {{ source('synthetic', 'orders') }}
)

select
    order_id,
    business_id,
    dasher_id,
    cast(order_timestamp as timestamp)      as order_timestamp,
    cast(order_date as date)                as order_date,
    date_trunc('month', order_date)         as order_month,
    extract(year from order_date)           as order_year,
    order_hour,
    order_day_of_week,
    cast(estimated_delivery_min as integer) as estimated_delivery_min,
    cast(actual_delivery_min    as integer) as actual_delivery_min,
    cast(delivery_delta_min     as integer) as delivery_delta_min,
    cast(is_on_time as boolean)             as is_on_time,
    cast(order_total_usd  as decimal(10,2)) as order_total_usd,
    cast(delivery_fee_usd as decimal(10,2)) as delivery_fee_usd,
    order_status,
    _is_synthetic

from source
where order_id is not null
