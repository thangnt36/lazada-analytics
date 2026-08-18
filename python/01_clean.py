"""
01_clean.py — Bước 1: gộp 2 gian hàng, loại bỏ dữ liệu cá nhân, chuẩn hoá kiểu dữ liệu.

Chạy:  python python/01_clean.py
Ra:    data/clean/orders_clean.parquet

Những chỗ đánh dấu TODO là phần bạn tự quyết định — đừng bỏ qua,
đó là phần người phỏng vấn sẽ hỏi.
"""

from pathlib import Path
import pandas as pd

RAW = Path("data/raw")
CLEAN = Path("data/clean")
CLEAN.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# 1. Các cột chứa thông tin cá nhân — LOẠI BỎ NGAY, không giữ lại bản nào
# ---------------------------------------------------------------------------
PII_COLS = [
    "customerName", "customerEmail", "nationalRegistrationNumber",
    "shippingName", "shippingAddress", "shippingAddress2", "shippingAddress3",
    "shippingAddress4", "shippingAddress5", "shippingPhone", "shippingPhone2",
    "shippingPostCode",
    "billingName", "billingAddr", "billingAddr2", "billingAddr3",
    "billingAddr4", "billingAddr5", "billingPhone", "billingPhone2",
    "billingPostCode",
    "taxCode", "branchNumber", "invoiceNumber",
    "trackingCode", "cdTrackingCode", "trackingUrl",
    "trackingCodeFM", "trackingUrlFM",
    "buyerFailedDeliveryUserName", "sellerNote",
]

# Cột rỗng hoàn toàn (100% NaN) trong bộ dữ liệu này — bỏ cho gọn.
# Đã kiểm tra bằng df.isna().mean(): wareHouse/walletCredit/refundAmount rỗng 100%.
# bundleDiscount rỗng 99,1% nhưng còn 286 dòng có giá trị thật (phí khuyến mãi
# gói sản phẩm) — GIỮ LẠI, không đưa vào danh sách này (xem docs/data_quality.md mục 3).
EMPTY_COLS = ["wareHouse", "walletCredit", "refundAmount"]

DATE_FMT = "%d %b %Y %H:%M"   # ví dụ: '14 Nov 2022 10:35'
DATE_COLS = ["createTime", "updateTime", "deliveredDate", "promisedShippingTime"]


def load_shop(filename: str, shop_name: str) -> pd.DataFrame:
    df = pd.read_excel(RAW / filename)
    df["shop"] = shop_name
    print(f"  {shop_name:<10} {len(df):>6,} dòng  {df.orderNumber.nunique():>6,} đơn")
    return df


def main():
    print("Đọc dữ liệu gốc:")
    df = pd.concat(
        [load_shop("Chetanic.xlsx", "Chetanic"),
         load_shop("Lumytive.xlsx", "Lumytive")],
        ignore_index=True,
    )
    print(f"  {'TỔNG':<10} {len(df):>6,} dòng  {df.orderNumber.nunique():>6,} đơn\n")

    # -----------------------------------------------------------------------
    # 2. Loại PII — làm ngay, trước mọi xử lý khác
    # -----------------------------------------------------------------------
    dropped = [c for c in PII_COLS if c in df.columns]
    df = df.drop(columns=dropped)
    print(f"Đã loại {len(dropped)} cột chứa thông tin cá nhân.")

    df = df.drop(columns=[c for c in EMPTY_COLS if c in df.columns])

    # -----------------------------------------------------------------------
    # 3. Chuẩn hoá kiểu dữ liệu
    # -----------------------------------------------------------------------
    for col in DATE_COLS:
        if col in df.columns:
            parsed = pd.to_datetime(df[col], format=DATE_FMT, errors="coerce")
            n_fail = parsed.isna().sum() - df[col].isna().sum()
            if n_fail > 0:
                print(f"  ! {col}: {n_fail:,} giá trị không parse được — kiểm tra lại")
            df[col] = parsed

    # Chiết khấu đang mang giá trị ÂM trong file gốc. Đổi về dương cho dễ cộng.
    # TODO: tự xác nhận bằng cách xem vài dòng trước khi tin bước này.
    for col in ["sellerDiscountTotal", "platformDiscountTotal"]:
        if col in df.columns:
            df[col] = df[col].fillna(0).abs()

    for col in ["paidPrice", "unitPrice", "shippingFee", "bundleDiscount"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    # -----------------------------------------------------------------------
    # 4. Trạng thái đơn: hoàn tất hay không
    # -----------------------------------------------------------------------
    COMPLETED = {"confirmed", "delivered"}
    df["is_completed"] = df["status"].isin(COMPLETED)

    print("\nPhân bố trạng thái:")
    for s, n in df.status.value_counts().items():
        print(f"  {str(s):<34} {n:>7,}  ({n/len(df)*100:>5.1f}%)")
    print(f"\n  Tỷ lệ dòng KHÔNG hoàn tất: {(~df.is_completed).mean()*100:.1f}%")

    # -----------------------------------------------------------------------
    # 5. Kiểm tra quan trọng nhất: paidPrice ở tầng nào?
    # -----------------------------------------------------------------------
    multi = df.groupby("orderNumber").size()
    sample_order = multi[multi > 1].index[0]
    print(f"\n{'='*70}")
    print("KIỂM TRA: paidPrice là giá theo DÒNG hay theo ĐƠN?")
    print(f"Đơn mẫu {sample_order} có {multi[sample_order]} dòng:")
    cols = [c for c in ["sellerSku", "unitPrice", "paidPrice", "shippingFee"] if c in df.columns]
    print(df.loc[df.orderNumber == sample_order, cols].to_string(index=False))
    print("\n>> TODO: đối chiếu với giá trị đơn bạn còn nhớ, rồi ghi kết luận")
    print(">>       vào docs/data_quality.md. Sai chỗ này thì mọi số sau đều lệch.")
    print("=" * 70)

    # -----------------------------------------------------------------------
    # 6. Lưu
    # -----------------------------------------------------------------------
    # TODO: itemName vẫn còn ở đây vì bước 2 cần nó để rút nhãn khuyến mãi
    #       ([FREESHIP], [TRỢ GIÁ 10K...]). Chỉ bỏ nó SAU khi đã rút xong.
    try:
        out = CLEAN / "orders_clean.parquet"
        df.to_parquet(out, index=False)
    except ImportError:
        out = CLEAN / "orders_clean.csv"
        df.to_csv(out, index=False, encoding="utf-8-sig")
        print("  (chưa có pyarrow nên lưu CSV — cài pyarrow để dùng parquet, nhẹ và nhanh hơn)")
    print(f"\nĐã lưu: {out}  ({len(df):,} dòng × {len(df.columns)} cột)")


if __name__ == "__main__":
    main()
