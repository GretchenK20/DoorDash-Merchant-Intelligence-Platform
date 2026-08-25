-- stg_yelp_reviews.sql
-- Silver layer: clean review records with derived fields

{{ config(enabled=(target.name != 'dev')) }}

with source as (
    select * from {{ source('bronze', 'reviews') }}
),

cleaned as (
    select
        review_id,
        user_id,
        business_id,
        cast(stars as decimal(2,1))             as review_stars,
        cast(useful as integer)                 as useful_votes,
        cast(funny  as integer)                 as funny_votes,
        cast(cool   as integer)                 as cool_votes,
        cast(review_date as date)               as review_date,
        date_trunc('month', review_date)        as review_month,
        extract(year  from review_date)         as review_year,
        extract(month from review_date)         as review_month_num,

        -- Simple sentiment bucketing from star rating
        -- (avoids NLP dependency while still enabling cohort analysis)
        case
            when stars >= 4  then 'positive'
            when stars = 3   then 'neutral'
            else                  'negative'
        end as sentiment_bucket,

        _ingested_at,
        _batch_date

    from source
    where
        review_id   is not null
        and business_id is not null
        and stars between 1 and 5
        and review_date is not null
        and review_date >= date '2015-01-01'  -- filter very old reviews
)

select * from cleaned
