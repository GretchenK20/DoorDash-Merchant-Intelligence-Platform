# Dashboard Build Guide
## DoorDash Merchant Intelligence Platform

Three dashboards, two tools: build in Tableau Public now (free, no cloud required),
then recreate in Sigma once Snowflake is connected — structure is identical.

---

## Data sources

| File | Rows | Use |
|---|---|---|
| `mart_merchant_performance.csv` | 2,000 | Tabs 1, 3 |
| `mart_cuisine_market_share.csv` | 100 | Tab 2 |
| `mart_reviewer_cohort_retention.csv` | 60 | Tab 2 |
| `mart_delivery_operations.csv` | 4,974 | Tab 3 |

Connect all four as separate data sources. Create relationships:
- `mart_delivery_operations` → `mart_merchant_performance` on `business_id`
- `mart_cuisine_market_share` → (standalone — state/cuisine grain)

---

## Tab 1 — Merchant Performance

**Purpose:** Which merchants are elite? Who's at risk? Filter by state, cuisine, tier.

### Sheet 1A — Performance Tier Distribution (Bar)
- Rows: `tier_label` (sort: Elite → Low)
- Cols: COUNT of `business_id`
- Color: `performance_tier` (diverging: red=1, green=5)
- Label: count
- Title: "Merchant Distribution by Tier"

### Sheet 1B — Composite Score by Cuisine (Box Plot)
- Rows: `composite_score`
- Cols: `primary_cuisine`
- Mark: Box-and-whisker
- Sort cuisine by median composite_score descending
- Title: "Score Distribution by Cuisine"

### Sheet 1C — Elite Merchants Map (Scatter on Map)
- Latitude: `latitude`, Longitude: `longitude`
- Filter: `is_elite_merchant = true`
- Color: `primary_cuisine`
- Size: `total_reviews`
- Tooltip: `business_name`, `avg_review_stars`, `reviews_per_month`
- Title: "Elite Merchant Locations"

### Sheet 1D — Review Velocity vs Stars (Scatter)
- X: `reviews_per_month`
- Y: `avg_review_stars`
- Color: `performance_tier`
- Size: `total_checkins`
- Reference lines: median for both axes (creates 4 quadrants)
- Quadrant labels: "Rising Stars" (top-left), "Champions" (top-right),
  "Fading" (bottom-right), "Struggling" (bottom-left)
- Title: "Review Velocity vs Quality"

### Dashboard 1 layout
```
[1C — Map (full width top)]
[1A — Tier Bar | 1D — Scatter]
[1B — Box Plot (full width)]
```
Filters (apply to all): State, Primary Cuisine, Is Open

---

## Tab 2 — Market Intelligence

**Purpose:** Which cuisines dominate which markets? Where are growth gaps?

### Sheet 2A — Market Share Heatmap
- Rows: `state`
- Cols: `primary_cuisine`
- Color: `market_share_pct` (sequential blue)
- Label: `merchant_count`
- Filter: top 10 states by total merchants
- Title: "Cuisine Market Share by State (%)"

### Sheet 2B — Cuisine Rankings (Horizontal Bar)
- Rows: `primary_cuisine` (sorted by `merchant_count` desc)
- Cols: `merchant_count`
- Color: `avg_composite_score` (diverging)
- Secondary axis: `avg_stars` (line)
- Title: "Cuisine Volume vs Quality"

### Sheet 2C — Cohort Retention (Line)
- Source: `mart_reviewer_cohort_retention`
- X: `months_since_cohort` (0–24)
- Y: `retention_rate_pct`
- Color: `cohort_label` (one line per cohort month)
- Filter: show last 6 cohort months only (avoid overplotting)
- Reference line at Y=20% (typical retention threshold)
- Title: "Monthly Reviewer Cohort Retention"
- Note in subtitle: "How many users who first reviewed in month X
  are still reviewing N months later"

### Sheet 2D — Elite Merchant Share by Cuisine (Treemap)
- Size: `merchant_count`
- Color: `elite_merchant_share`
- Label: `primary_cuisine`
- Title: "Elite Merchant Concentration by Cuisine"

### Dashboard 2 layout
```
[2A — Heatmap (left half) | 2C — Cohort Retention (right half)]
[2B — Rankings (left half) | 2D — Treemap (right half)]
```
Filters: State

---

## Tab 3 — Operations (Synthetic Data)

**Note:** Label clearly — "Powered by synthetic order data (illustrative)"
This is standard practice for portfolio work. In production this would
connect to real DoorDash order data.

### Sheet 3A — Fulfillment Rate by Merchant Tier (Bar)
- Rows: `tier_label`
- Cols: AVG(`fulfillment_rate`) → format as %
- Color: diverging (red < 90%, green ≥ 96%)
- Reference line: 95% target
- Title: "Fulfillment Rate by Merchant Tier"

### Sheet 3B — On-Time Rate by Day of Week (Bar)
- Rows: `order_day_of_week` (Mon–Sun sort)
- Cols: AVG(`on_time_rate`) → format as %
- Color: `on_time_rate`
- Title: "On-Time Delivery by Day of Week"

### Sheet 3C — GMV by Cuisine (Treemap)
- Size: SUM(`total_gmv_usd`)
- Color: AVG(`avg_order_value_usd`)
- Label: `primary_cuisine` + formatted GMV
- Title: "Total GMV by Cuisine Category (Synthetic)"

### Sheet 3D — Delivery Time Distribution (Histogram)
- Source: `mart_delivery_operations`
- X: `avg_delivery_min` (bins of 2 min)
- Y: COUNT
- Reference lines: 30 min, 45 min
- Color: `performance_tier`
- Title: "Average Delivery Time Distribution"

### Sheet 3E — Monthly GMV Trend (Line)
- X: `order_month`
- Y: SUM(`total_gmv_usd`)
- Color: `primary_cuisine` (top 5 cuisines)
- Title: "Monthly GMV Trend by Cuisine (Synthetic)"

### Dashboard 3 layout
```
[3E — GMV Trend (full width)]
[3A — Fulfillment | 3B — On-Time | 3C — GMV Treemap]
[3D — Delivery Distribution (full width)]
```
Subtitle banner: ⚠ "Operations data is synthetic (illustrative).
See mart_delivery_operations._is_synthetic_data for details."

---

## Sigma-specific notes (when on Snowflake)

Sigma's spreadsheet model means you build these differently:
- Start with a "Data" page: drag each mart table in as a table element
- Duplicate rows and apply aggregations inline (like Excel pivot)
- Charts in Sigma are created from table columns directly
- Use "Controls" (= Tableau filters) for State, Cuisine, Tier
- Save as a "Workbook" → share via link (12,000 internal users at DoorDash use this pattern)

The key Sigma concept to demo: **self-serve**. A business stakeholder
(e.g., a Merchant Ops manager) can open the workbook, filter to their
state, drill into cuisine rankings, and export — without writing SQL.
That's what the analytics engineering team builds for.

---

## Publishing

**Tableau Public:**
1. File → Save to Tableau Public As → "DoorDash Merchant Intelligence Platform"
2. Copy the public URL
3. Add to GitHub README as "Live Dashboard" link
4. Add to resume under the project bullet

**Sigma (after Snowflake setup):**
1. Share workbook → "Anyone with link can view"
2. Take screenshots of each dashboard tab for README
3. Add Sigma URL to GitHub README
