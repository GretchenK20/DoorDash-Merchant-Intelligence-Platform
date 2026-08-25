-- int_merchant_activity.sql
-- Joins businesses ← reviews ← checkins into a single merchant activity grain.
-- This is the canonical "merchant universe" table all marts build from.

with businesses as (
    {% if target.name == 'dev' %}
    select * from {{ ref('stg_yelp_businesses_dev') }}
    {% else %}
    select * from {{ ref('stg_yelp_businesses') }}
    {% endif %}
),

review_agg as (
    select
        business_id,
        count(*)                                    as total_reviews,
        avg(review_stars)                           as avg_review_stars,
        min(review_date)                            as first_review_date,
        max(review_date)                            as last_review_date,
        -- Review velocity: reviews per month since first review
        count(*) / nullif(
            {{ months_diff('min(review_date)', 'max(review_date)') }}, 0
        )                                           as reviews_per_month,
        sum(case when sentiment_bucket = 'positive' then 1 else 0 end)
                                                    as positive_reviews,
        sum(case when sentiment_bucket = 'negative' then 1 else 0 end)
                                                    as negative_reviews,
        count(distinct review_year)                 as active_years

    from {% if target.name == 'dev' %}{{ ref('stg_yelp_reviews_dev') }}{% else %}{{ ref('stg_yelp_reviews') }}{% endif %}
    group by 1
),

checkin_agg as (
    select
        business_id,
        sum(checkin_count)                          as total_checkins,
        count(distinct checkin_date)                as active_checkin_days,
        -- Peak day of week (mode) — arg_max is DuckDB syntax
        arg_max(day_of_week, checkin_count)         as peak_day_of_week

    from {% if target.name == 'dev' %}{{ ref('stg_yelp_checkins_dev') }}{% else %}{{ ref('stg_yelp_checkins') }}{% endif %}
    group by 1
)

select
    b.business_id,
    b.business_name,
    b.city,
    b.state,
    b.primary_cuisine,
    b.stars                                         as yelp_stars,
    b.review_count                                  as yelp_review_count,
    b.is_open,
    b.latitude,
    b.longitude,

    -- Review-derived metrics
    coalesce(r.total_reviews,       0)              as total_reviews,
    coalesce(r.avg_review_stars,    b.stars)        as avg_review_stars,
    r.first_review_date,
    r.last_review_date,
    coalesce(r.reviews_per_month,   0)              as reviews_per_month,
    coalesce(r.positive_reviews,    0)              as positive_reviews,
    coalesce(r.negative_reviews,    0)              as negative_reviews,
    coalesce(r.active_years,        0)              as active_years,

    -- Positive review ratio
    case
        when coalesce(r.total_reviews, 0) = 0 then null
        else cast(r.positive_reviews as double) / r.total_reviews
    end                                             as positive_review_ratio,

    -- Checkin-derived metrics
    coalesce(c.total_checkins,      0)              as total_checkins,
    coalesce(c.active_checkin_days, 0)              as active_checkin_days,
    c.peak_day_of_week

from businesses b
left join review_agg  r using (business_id)
left join checkin_agg c using (business_id)
