-- stg_yelp_businesses.sql
-- Silver layer: clean, typed, filtered business records
-- Filters to food/restaurant category only (DoorDash's merchant universe)
-- Production only (--target trino). Use stg_yelp_businesses_dev for local dev.

{{ config(enabled=(target.name != 'dev')) }}

with source as (
    select * from {{ source('bronze', 'businesses') }}
),

cleaned as (
    select
        business_id,
        trim(name)                                      as business_name,
        trim(address)                                   as address,
        trim(city)                                      as city,
        upper(trim(state))                              as state,
        postal_code,
        cast(latitude  as double)                       as latitude,
        cast(longitude as double)                       as longitude,
        cast(stars as decimal(2,1))                     as stars,
        cast(review_count as integer)                   as review_count,
        cast(is_open as boolean)                        as is_open,
        trim(categories)                                as categories_raw,
        _ingested_at,
        _batch_date

    from source

    where
        -- Must have coordinates (needed for market analysis)
        latitude  is not null
        and longitude is not null
        -- Must have a valid star rating
        and stars between 1.0 and 5.0
        -- Must have a minimum review count (filter noise)
        and review_count > 0
        -- Filter to food-adjacent businesses only
        and (
            lower(categories) like '%restaurant%'
            or lower(categories) like '%food%'
            or lower(categories) like '%pizza%'
            or lower(categories) like '%burger%'
            or lower(categories) like '%cafe%'
            or lower(categories) like '%coffee%'
            or lower(categories) like '%sushi%'
            or lower(categories) like '%bar%'
            or lower(categories) like '%bakery%'
            or lower(categories) like '%diner%'
            or lower(categories) like '%grill%'
            or lower(categories) like '%bistro%'
            or lower(categories) like '%thai%'
            or lower(categories) like '%mexican%'
            or lower(categories) like '%italian%'
            or lower(categories) like '%chinese%'
        )
),

-- Parse primary cuisine from categories string
-- (takes first recognized cuisine keyword — simplified taxonomy)
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
            when lower(categories_raw) like '%sandwich%'     then 'Sandwiches'
            when lower(categories_raw) like '%coffee%'       then 'Coffee & Tea'
            when lower(categories_raw) like '%cafe%'         then 'Coffee & Tea'
            when lower(categories_raw) like '%bakery%'       then 'Bakery'
            when lower(categories_raw) like '%bar%'
             and lower(categories_raw) like '%food%'         then 'Bars & Grills'
            when lower(categories_raw) like '%diner%'        then 'American (Traditional)'
            when lower(categories_raw) like '%american%'     then 'American (New)'
            when lower(categories_raw) like '%seafood%'      then 'Seafood'
            when lower(categories_raw) like '%indian%'       then 'Indian'
            when lower(categories_raw) like '%korean%'       then 'Korean'
            when lower(categories_raw) like '%vietnamese%'   then 'Vietnamese'
            when lower(categories_raw) like '%mediterranean%' then 'Mediterranean'
            else 'Other'
        end as primary_cuisine

    from cleaned
)

select * from with_cuisine
