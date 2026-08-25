-- mart_reviewer_cohort_retention.sql
-- Monthly reviewer cohort retention analysis.
-- Shows: of users who first reviewed in month X,
--        what % are still reviewing N months later?
--
-- Demonstrates A/B testing / experimentation data literacy
-- (explicitly called out in DoorDash JD).

with reviews as (
    select
        user_id,
        review_month,
        review_year
    from {% if target.name == 'dev' %}{{ ref('stg_yelp_reviews_dev') }}{% else %}{{ ref('stg_yelp_reviews') }}{% endif %}
    where user_id is not null
),

-- Each user's first review month = their cohort
user_cohorts as (
    select
        user_id,
        min(review_month) as cohort_month
    from reviews
    group by 1
),

-- Cross-join: for each user, what months did they review in?
user_activity as (
    select
        r.user_id,
        uc.cohort_month,
        r.review_month                          as activity_month,
        -- Months since cohort start
        {{ months_diff('cast(uc.cohort_month as date)', 'cast(r.review_month as date)') }}
                                                as months_since_cohort

    from reviews r
    join user_cohorts uc using (user_id)
),

-- Cohort sizes
cohort_sizes as (
    select
        cohort_month,
        count(distinct user_id) as cohort_size
    from user_cohorts
    group by 1
),

-- Retention: # of users from cohort still active at month N
retention as (
    select
        cohort_month,
        months_since_cohort,
        count(distinct user_id) as retained_users

    from user_activity
    group by 1, 2
)

select
    r.cohort_month,
    strftime(cast(r.cohort_month as date), '%Y-%m') as cohort_label,
    r.months_since_cohort,
    cs.cohort_size,
    r.retained_users,
    round(
        100.0 * r.retained_users / nullif(cs.cohort_size, 0),
        2
    )                                           as retention_rate_pct

from retention r
join cohort_sizes cs using (cohort_month)

-- Cap at 24 months for dashboard readability
where r.months_since_cohort between 0 and 24

order by r.cohort_month, r.months_since_cohort
