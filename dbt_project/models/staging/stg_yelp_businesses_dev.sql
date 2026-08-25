-- stg_yelp_businesses_dev.sql
-- Dev-only model: reads from dbt seed (bronze_businesses)
-- instead of Delta Lake source. Identical transformations to
-- stg_yelp_businesses — used for local dev and CI.
-- In production (--target trino), use stg_yelp_businesses.sql

{{ config(enabled=(target.name == 'dev')) }}

with source as (
    select * from {{ ref('bronze_businesses') }}
),

cleaned as (
    select
        business_id,
        trim(name)                              as business_name,
        trim(address)                           as address,
        trim(city)                              as city,
        upper(trim(state))                      as state,
        postal_code,
        cast(latitude  as double)               as latitude,
        cast(longitude as double)               as longitude,
        cast(stars as double)                   as stars,
        cast(review_count as integer)           as review_count,
        cast(is_open as boolean)                as is_open,
        trim(categories)                        as categories_raw,
        cast(_ingested_at as timestamp)         as _ingested_at,
        cast(_batch_date as date)               as _batch_date

    from source
    where
        latitude  is not null
        and longitude is not null
        and cast(stars as double) between 1.0 and 5.0
        and cast(review_count as integer) > 0
),

with_cuisine as (
    select
        *,
        case
            when lower(categories_raw) like '%pizza%'        then 'Pizza'
            when lower(categories_raw) like '%sushi%'        then 'Sushi'
            when lower(categories_raw) like '%thai%'         then 'Thai'
            when lower(categories_raw) like '%mexican%'      then 'Mexican'
            when lower(categories_raw) like '%italian%'      then 'Italian'
            when lower(categories_raw) like '%chinese%'      then 'Chinese'
            when lower(categories_raw) like '%burger%'       then 'Burgers'
            when lower(categories_raw) like '%coffee%'       then 'Coffee & Tea'
            when lower(categories_raw) like '%cafe%'         then 'Coffee & Tea'
            when lower(categories_raw) like '%bakery%'       then 'Bakery'
            when lower(categories_raw) like '%american%'     then 'American (New)'
            when lower(categories_raw) like '%seafood%'      then 'Seafood'
            else categories_raw
        end as primary_cuisine

    from cleaned
)

select * from with_cuisine
