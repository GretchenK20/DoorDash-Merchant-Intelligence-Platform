-- stg_yelp_reviews_dev.sql
-- Dev-only: reads from bronze_reviews seed instead of Delta Lake source.
-- Identical transformations to stg_yelp_reviews.sql.

{{ config(enabled=(target.name == 'dev')) }}

with source as (
    select * from {{ ref('bronze_reviews') }}
),

cleaned as (
    select
        review_id,
        user_id,
        business_id,
        cast(stars as double)                           as review_stars,
        cast(useful as integer)                         as useful_votes,
        cast(funny  as integer)                         as funny_votes,
        cast(cool   as integer)                         as cool_votes,
        cast(review_date as date)                       as review_date,
        date_trunc('month', cast(review_date as date))  as review_month,
        year(cast(review_date as date))                 as review_year,
        month(cast(review_date as date))                as review_month_num,

        case
            when cast(stars as double) >= 4  then 'positive'
            when cast(stars as double) = 3   then 'neutral'
            else                                  'negative'
        end as sentiment_bucket,

        cast(_ingested_at as timestamp)                 as _ingested_at,
        cast(_batch_date as date)                       as _batch_date

    from source
    where
        review_id   is not null
        and business_id is not null
        and cast(stars as double) between 1 and 5
        and review_date is not null
)

select * from cleaned
