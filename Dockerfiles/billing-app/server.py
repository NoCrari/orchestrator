from app.consume_queue import consume_and_store_order
from app.orders import Base

from sqlalchemy import create_engine, text

import os
import time


BILLING_DB_USER = os.getenv("BILLING_DB_USER")
BILLING_DB_PASSWORD = os.getenv("BILLING_DB_PASSWORD")
BILLING_DB_NAME = os.getenv("BILLING_DB_NAME")

DB_URI = (
    "postgresql://"
    f'{BILLING_DB_USER}:{BILLING_DB_PASSWORD}'
    f'@billing-db:5432/{BILLING_DB_NAME}'
)

engine = create_engine(DB_URI)

# Robust DB readiness loop before creating tables
for attempt in range(90):  # ~3 minutes
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        break
    except Exception as e:
        print(f"[billing-app] DB not ready (attempt {attempt+1}): {e}")
        time.sleep(2)

Base.metadata.create_all(engine)

consume_and_store_order(engine)
