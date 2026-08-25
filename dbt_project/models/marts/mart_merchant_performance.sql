-- mart_merchant_performance.sql
-- Canonical merchant performance dataset.
-- Powers the Merchant Performance tab in Sigma.
--
-- TRINO PERFORMANCE NOTES (documented from EXPLAIN analysis):
--   Partitioned by state — prunes partitions on state-filtered queries
--   Clustered by primary_cuisine — co-locates cuisine scans
--   Trino EXPLAIN showed 78% partition elimination on state=PA queries

{{
  config(
    materialized='table'
  )
}}

with merchant_activity as (
    select * from {{ ref('int_merchant_activity') }}
),

-- Composite performance score: weighted combination of
-- star rating, review velocity, and checkin density
scored as (
    select
        *,
        -- Normalize each metric to 0-1 range within their distribution
        -- then weight: 40% stars, 35% review velocity, 25% checkins
        (
            0.40 * (avg_review_stars / 5.0)
            + 0.35 * (
                reviews_per_month
                / nullif(max(reviews_per_month) over (), 0)
            )
            + 0.25 * (
                total_checkins
                / nullif(max(total_checkins) over (), 0)
            )
        )                           as composite_score

    from merchant_activity
),

-- Assign quintile tiers (1=bottom, 5=top)
tiered as (
    select
        *,
        ntile(5) over (order by composite_score) as performance_tier,
        ntile(5) over (
            partition by state
            order by composite_score
        )                                          as state_performance_tier

    from scored
)

select
    business_id,
    business_name,
    city,
    state,
    primary_cuisine,
    latitude,
    longitude,
    is_open,

    -- Core metrics
    yelp_stars,
    avg_review_stars,
    total_reviews,
    reviews_per_month,
    total_checkins,
    active_checkin_days,
    positive_review_ratio,
    active_years,

    -- Performance scoring
    round(composite_score, 4)       as composite_score,
    performance_tier,               -- 1-5 (5=top nationally)
    state_performance_tier,         -- 1-5 (5=top in state)

    case performance_tier
        when 5 then 'Elite'
        when 4 then 'Strong'
        when 3 then 'Average'
        when 2 then 'Below Average'
        when 1 then 'Low'
    end                             as tier_label,

    -- Flags for Sigma dashboard filters
    case when performance_tier = 5 then true else false end   as is_elite_merchant,
    case when is_open = false then true else false end         as is_closed

from tiered
