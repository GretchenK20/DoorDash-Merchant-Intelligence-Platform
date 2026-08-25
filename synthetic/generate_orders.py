"""
generate_orders.py
──────────────────
Generates ~500K synthetic order events keyed to real Yelp business_ids.
This adds the delivery/operations dimension the static Yelp data lacks —
enabling mart_delivery_operations (fulfillment rate, on-time %, GMV).

Clearly labeled synthetic throughout: column _is_synthetic=True,
README notes it, dashboard labels note it. No misrepresentation.

Output: data/synthetic/orders.parquet
"""

import argparse
import json
import os
import random
from datetime import datetime, timedelta

import pandas as pd
from faker import Faker

fake = Faker()
random.seed(42)

# ── Config ────────────────────────────────────────────────────────────────────

N_ORDERS          = 500_000
START_DATE        = datetime(2022, 1, 1)
END_DATE          = datetime(2024, 12, 31)
DATE_RANGE_DAYS   = (END_DATE - START_DATE).days

# Delivery time distributions (minutes) — modeled on real delivery patterns
EST_DELIVERY_MEAN = 35
EST_DELIVERY_STD  = 8
ACTUAL_DELTA_MEAN = 0       # on-time on average
ACTUAL_DELTA_STD  = 12      # ±12 min std dev

# Order value distribution
ORDER_MIN   = 8.00
ORDER_MAX   = 120.00
ORDER_MEAN  = 28.50
ORDER_STD   = 15.00

# Cancellation rate
CANCEL_RATE = 0.04

# Dasher pool
N_DASHERS = 5_000


def load_business_ids(yelp_data_dir: str) -> list[str]:
    """Load real business_ids from Yelp dataset (food businesses only)."""
    path = os.path.join(yelp_data_dir, "yelp_academic_dataset_business.json")
    if not os.path.exists(path):
        print(f"  ⚠ Yelp data not found at {path}")
        print("  → Generating placeholder business IDs for schema validation")
        return [fake.uuid4() for _ in range(10_000)]

    ids = []
    food_keywords = {"restaurant", "food", "pizza", "burger", "cafe",
                     "sushi", "thai", "mexican", "italian", "chinese",
                     "bakery", "diner", "bar", "grill", "bistro"}

    with open(path) as f:
        for line in f:
            biz = json.loads(line)
            cats = (biz.get("categories") or "").lower()
            if any(k in cats for k in food_keywords):
                ids.append(biz["business_id"])

    print(f"  Loaded {len(ids):,} food business IDs from Yelp dataset")
    return ids


def generate_orders(business_ids: list[str], n: int) -> pd.DataFrame:
    """Generate synthetic order events."""
    print(f"  Generating {n:,} synthetic orders...")

    dasher_ids = [f"DASHER_{i:05d}" for i in range(N_DASHERS)]

    records = []
    for _ in range(n):
        biz_id = random.choice(business_ids)

        # Timestamp — weighted toward evenings and weekends
        day_offset  = random.randint(0, DATE_RANGE_DAYS)
        # Dinner peak: 5-9pm most common
        hour = random.choices(
            range(24),
            weights=[1,1,1,1,1,1,2,3,4,5,5,4,5,4,4,4,5,6,8,9,9,8,6,3],
            k=1
        )[0]
        minute = random.randint(0, 59)
        ts = START_DATE + timedelta(days=day_offset, hours=hour, minutes=minute)

        est_delivery = max(15, int(random.gauss(EST_DELIVERY_MEAN, EST_DELIVERY_STD)))
        actual_delta = int(random.gauss(ACTUAL_DELTA_MEAN, ACTUAL_DELTA_STD))
        actual_delivery = max(10, est_delivery + actual_delta)

        # Order value — clipped normal
        order_total = round(min(ORDER_MAX, max(ORDER_MIN,
                            random.gauss(ORDER_MEAN, ORDER_STD))), 2)
        delivery_fee = round(random.uniform(0.99, 7.99), 2)

        is_cancelled = random.random() < CANCEL_RATE
        status = "cancelled" if is_cancelled else "delivered"

        records.append({
            "order_id":                 fake.uuid4(),
            "business_id":              biz_id,
            "dasher_id":                random.choice(dasher_ids),
            "order_timestamp":          ts,
            "order_date":               ts.date(),
            "order_hour":               hour,
            "order_day_of_week":        ts.strftime("%A"),
            "estimated_delivery_min":   est_delivery,
            "actual_delivery_min":      actual_delivery if not is_cancelled else None,
            "delivery_delta_min":       actual_delta if not is_cancelled else None,
            "is_on_time":               (actual_delta <= 5) if not is_cancelled else None,
            "order_total_usd":          order_total,
            "delivery_fee_usd":         delivery_fee,
            "order_status":             status,
            "_is_synthetic":            True,
        })

    return pd.DataFrame(records)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--yelp_data_dir", default="./data/yelp_dataset")
    parser.add_argument("--output",        default="./data/synthetic/orders.parquet")
    parser.add_argument("--n_orders",      type=int, default=N_ORDERS)
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    print(f"\n{'='*60}")
    print("Synthetic Order Generator")
    print(f"  N orders : {args.n_orders:,}")
    print(f"  Output   : {args.output}")
    print(f"{'='*60}\n")

    business_ids = load_business_ids(args.yelp_data_dir)
    df = generate_orders(business_ids, args.n_orders)

    df.to_parquet(args.output, index=False)
    print(f"\n✓ Written {len(df):,} orders → {args.output}")

    # Quick QA summary
    print("\n── QA Summary ──────────────────────────────────────────")
    print(f"  Date range      : {df['order_date'].min()} → {df['order_date'].max()}")
    print(f"  Unique merchants: {df['business_id'].nunique():,}")
    print(f"  Cancellation %  : {(df['order_status']=='cancelled').mean():.1%}")
    print(f"  Avg order total : ${df['order_total_usd'].mean():.2f}")
    delivered = df[df['order_status'] == 'delivered']
    print(f"  On-time %       : {delivered['is_on_time'].mean():.1%}")
    print(f"  Avg delivery    : {delivered['actual_delivery_min'].mean():.1f} min")


if __name__ == "__main__":
    main()
