-- stg_yelp_checkins_dev.sql
-- Dev-only: reads from bronze_checkins seed instead of Delta Lake source.

{{ config(enabled=(target.name == 'dev')) }}

with source as (
    select * from {{ ref('bronze_checkins') }}
),

daily_agg as (
    select
        business_id,
        cast(checkin_at as date)                            as checkin_date,
        date_trunc('month', cast(checkin_at as timestamp))  as checkin_month,
        year(cast(checkin_at as timestamp))                 as checkin_year,
        dayofweek(cast(checkin_at as timestamp))            as day_of_week,
        hour(cast(checkin_at as timestamp))                 as hour_of_day,
        count(*)                                            as checkin_count

    from source
    where checkin_at is not null

    group by 1, 2, 3, 4, 5, 6
)

select * from daily_agg
