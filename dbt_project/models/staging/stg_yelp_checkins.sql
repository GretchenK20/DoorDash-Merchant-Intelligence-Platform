-- stg_yelp_checkins.sql
-- Silver layer: checkin events aggregated to daily counts
-- (proxy for foot traffic / demand signal)

{{ config(enabled=(target.name != 'dev')) }}

with source as (
    select * from {{ source('bronze', 'checkins') }}
),

daily_agg as (
    select
        business_id,
        cast(checkin_at as date)        as checkin_date,
        date_trunc('month', checkin_at) as checkin_month,
        extract(year  from checkin_at)  as checkin_year,
        extract(dow   from checkin_at)  as day_of_week,   -- 0=Sun
        extract(hour  from checkin_at)  as hour_of_day,
        count(*)                        as checkin_count

    from source
    where checkin_at is not null

    group by 1, 2, 3, 4, 5, 6
)

select * from daily_agg
