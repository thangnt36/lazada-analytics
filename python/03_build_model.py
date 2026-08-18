"""
03_build_model.py — Bước 4: chạy sql/01_schema.sql để dựng star schema trong DuckDB.

Chạy:  python python/03_build_model.py
Ra:    data/clean/lazada.duckdb
"""

from pathlib import Path

import duckdb

DB_PATH = Path("data/clean/lazada.duckdb")
SCHEMA_SQL = Path("sql/01_schema.sql")

TABLES = ["fact_order_item", "dim_order", "dim_product", "dim_date", "dim_shipping_provider"]


def main():
    con = duckdb.connect(str(DB_PATH))
    con.execute(SCHEMA_SQL.read_text(encoding="utf-8"))

    print("So dong moi bang:")
    for t in TABLES:
        n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"  {t:<24} {n:>7,}")

    print("\nKiem tra khoa:")
    dup_item = con.execute(
        "SELECT COUNT(*) FROM (SELECT orderItemId FROM fact_order_item GROUP BY orderItemId HAVING COUNT(*) > 1)"
    ).fetchone()[0]
    print(f"  orderItemId trung lap trong fact_order_item: {dup_item}")

    dup_order = con.execute(
        "SELECT COUNT(*) FROM (SELECT orderNumber, shop FROM dim_order GROUP BY orderNumber, shop HAVING COUNT(*) > 1)"
    ).fetchone()[0]
    print(f"  (orderNumber, shop) trung lap trong dim_order: {dup_order}")

    dup_product = con.execute(
        "SELECT COUNT(*) FROM (SELECT product_code FROM dim_product GROUP BY product_code HAVING COUNT(*) > 1)"
    ).fetchone()[0]
    print(f"  product_code trung lap trong dim_product: {dup_product}")

    n_no_cost = con.execute("SELECT COUNT(*) FROM dim_product WHERE gia_nhap IS NULL").fetchone()[0]
    print(f"  product_code chua co gia von (NULL): {n_no_cost}")

    print("\nDoi chieu tong SUM(paidPrice): fact_order_item vs dim_order")
    total_fact = con.execute("SELECT SUM(paidPrice) FROM fact_order_item").fetchone()[0]
    total_dim = con.execute("SELECT SUM(total_paid_price) FROM dim_order").fetchone()[0]
    print(f"  fact_order_item: {total_fact:,.0f}")
    print(f"  dim_order:       {total_dim:,.0f}")
    print(f"  Khop: {total_fact == total_dim}")

    con.close()
    print(f"\nDa luu: {DB_PATH}")


if __name__ == "__main__":
    main()
