-- mart_delivery_operations.sql
-- Delivery operations metrics by merchant, month, and day of week.
-- Based on synthetic order data — labeled throughout.
-- Powers the Operations tab in Sigma.

with orders as (
    select * from {% if target.name == 'dev' %}{{ ref('stg_synthetic_orders_dev') }}{% else %}{{ ref('stg_synthetic_orders') }}{% endif %}
    where _is_synthetic = true  -- explicit guard: only synthetic rows
),

merchants as (
    select
        business_id,
        business_name,
        city,
        state,
        primary_cuisine,
        performance_tier,
        tier_label
    from {{ ref('mart_merchant_performance') }}
),

order_metrics as (
    select
        o.business_id,
        o.order_month,
        o.order_day_of_week,

        count(*)                                        as total_orders,
        sum(case when order_status = 'delivered'
                 then 1 else 0 end)                     as delivered_orders,
        sum(case when order_status = 'cancelled'
                 then 1 else 0 end)                     as cancelled_orders,

        -- Fulfillment rate
        avg(case when order_status = 'delivered'
                 then 1.0 else 0.0 end)                 as fulfillment_rate,

        -- On-time rate (among delivered orders)
        avg(case when order_status = 'delivered'
                 then cast(is_on_time as double) end)    as on_time_rate,

        -- Delivery time stats
        avg(case when order_status = 'delivered'
                 then actual_delivery_min end)           as avg_delivery_min,
        percentile_cont(0.90) within group (
            order by cast(actual_delivery_min as double)
        )                                                as p90_delivery_min,

        -- Revenue
        sum(order_total_usd)                            as total_gmv_usd,
        avg(order_total_usd)                            as avg_order_value_usd,
        sum(delivery_fee_usd)                           as total_delivery_fees_usd

    from orders o
    group by 1, 2, 3
)

select
    om.business_id,
    m.business_name,
    m.city,
    m.state,
    m.primary_cuisine,
    m.performance_tier,
    m.tier_label,
    om.order_month,
    om.order_day_of_week,

    -- Volume
    om.total_orders,
    om.delivered_orders,
    om.cancelled_orders,

    -- Quality metrics
    round(om.fulfillment_rate, 4)           as fulfillment_rate,
    round(om.on_time_rate, 4)               as on_time_rate,
    round(om.avg_delivery_min, 1)           as avg_delivery_min,
    round(om.p90_delivery_min, 1)           as p90_delivery_min,

    -- Revenue
    round(om.total_gmv_usd, 2)             as total_gmv_usd,
    round(om.avg_order_value_usd, 2)       as avg_order_value_usd,
    round(om.total_delivery_fees_usd, 2)   as total_delivery_fees_usd,

    -- Explicit synthetic label for dashboard and downstream consumers
    true                                    as _is_synthetic_data

from order_metrics om
join merchants m using (business_id)
