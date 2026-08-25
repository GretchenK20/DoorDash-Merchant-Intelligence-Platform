-- mart_cuisine_market_share.sql
-- Cuisine category penetration and performance by market (state/city).
-- Powers the Market Intelligence tab in Sigma.

with merchants as (
    select * from {{ ref('mart_merchant_performance') }}
),

state_totals as (
    select
        state,
        count(*) as total_merchants_in_state
    from merchants
    group by 1
),

cuisine_state as (
    select
        m.state,
        m.primary_cuisine,
        count(*)                        as merchant_count,
        avg(m.avg_review_stars)         as avg_stars,
        avg(m.reviews_per_month)        as avg_reviews_per_month,
        avg(m.total_checkins)           as avg_checkins,
        avg(m.composite_score)          as avg_composite_score,
        sum(m.total_reviews)            as total_reviews_in_segment,
        sum(case when m.is_open then 1 else 0 end) as open_merchant_count,
        -- Elite merchant share within cuisine+state
        avg(case when m.is_elite_merchant then 1.0 else 0.0 end)
                                        as elite_merchant_share

    from merchants m
    group by 1, 2
)

select
    cs.state,
    cs.primary_cuisine,
    cs.merchant_count,
    st.total_merchants_in_state,

    -- Market share = this cuisine's % of total merchants in state
    round(
        100.0 * cs.merchant_count / nullif(st.total_merchants_in_state, 0),
        2
    )                                   as market_share_pct,

    -- Performance metrics
    round(cs.avg_stars, 2)              as avg_stars,
    round(cs.avg_reviews_per_month, 2)  as avg_reviews_per_month,
    round(cs.avg_checkins, 0)           as avg_checkins,
    round(cs.avg_composite_score, 4)    as avg_composite_score,
    cs.total_reviews_in_segment,
    cs.open_merchant_count,
    round(cs.elite_merchant_share, 4)   as elite_merchant_share,

    -- Rank within state by merchant count
    rank() over (
        partition by cs.state
        order by cs.merchant_count desc
    )                                   as cuisine_rank_in_state

from cuisine_state cs
join state_totals  st using (state)
