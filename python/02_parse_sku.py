"""
02_parse_sku.py — Bước 3: tách product_code, campaign_flag, has_gift, promo_label
từ sellerSku (hậu tố chiến dịch) và itemName (nhãn khuyến mãi trong ngoặc vuông).

Chạy:  python python/02_parse_sku.py
Vào:   data/clean/orders_clean.parquet (từ 01_clean.py)
Ra:    data/clean/orders_parsed.parquet

Các quyết định thiết kế (xem docs/data_quality.md mục 6, 10 và 11):
- Hậu tố chiến dịch không đồng nhất trong dữ liệu thật: có dạng sạch (-FS),
  có dạng dính liền không dấu gạch ngang (CTFS, HRMN-coolFS, KCKDHS01-tunhienFS2).
  -> Bắt bằng regex ở CUỐI chuỗi, không bắt buộc có dấu "-" phía trước.
- -1sticker / -2sticker / -1stickera: coi cùng một ý nghĩa (có quà tặng kèm).
- -SL: cũng coi là has_gift=True (đã xác nhận với người vận hành thực tế).
- Mã gốc trong bảng ánh xạ giá vốn (Bang_anh_xa_SKU_giavon.xlsx) có độ chi tiết
  KHÔNG đồng nhất: SHRTT01 chỉ là tiền tố (campaign nằm ở phần đuôi bị cắt),
  còn CTFS/CTSL lại là mã gốc trọn vẹn — campaign đã dính liền và được coi là
  sản phẩm riêng trong bảng giá vốn. Vì vậy product_code ở đây LUÔN khớp theo
  mã gốc dài nhất làm prefix của sellerSku, không tự strip suffix thêm — để
  không phá vỡ khớp nối với sku_mapping.csv ở Bước 4.
"""

import re
from pathlib import Path

import pandas as pd

CLEAN = Path("data/clean")
MAPPING_XLSX = Path("Bang_anh_xa_SKU_giavon.xlsx")

# re.search (không anchor đầu) vì chỉ cần khớp phần ĐUÔI chuỗi.
FS_RE = re.compile(r"FS([23])?$", re.IGNORECASE)
SL_RE = re.compile(r"SL([23])?$", re.IGNORECASE)
STICKER_RE = re.compile(r"(\d)?stickera?$", re.IGNORECASE)

PROMO_LABEL_RE = re.compile(r"^\[([^\]]+)\]")


def load_base_codes() -> list[str]:
    """196 'Ma goc (base)' đã được điền tay ở Bước 2 — sort giảm dần theo độ
    dài để ưu tiên khớp mã dài/cụ thể nhất trước (vd. CTFS trước CT)."""
    df = pd.read_excel(MAPPING_XLSX, sheet_name="Anh xa SKU")
    codes = df["Ma goc (base)"].dropna().astype(str).unique().tolist()
    return sorted(codes, key=len, reverse=True)


def extract_product_code(sku: str, base_codes_upper: list[str]) -> str | None:
    sku_upper = sku.upper()
    for code_upper, code_orig in base_codes_upper:
        if sku_upper.startswith(code_upper):
            return code_orig
    return None


def extract_campaign_flag(sku: str) -> str | None:
    m = FS_RE.search(sku)
    return "FS" + (m.group(1) or "") if m else None


def extract_has_gift(sku: str) -> bool:
    return bool(STICKER_RE.search(sku)) or bool(SL_RE.search(sku))


def extract_promo_label(item_name: str) -> str | None:
    m = PROMO_LABEL_RE.match(item_name.strip())
    return m.group(1) if m else None


def main():
    df = pd.read_parquet(CLEAN / "orders_clean.parquet")

    base_codes = load_base_codes()
    base_codes_upper = [(c.upper(), c) for c in base_codes]
    print(f"Da doc {len(base_codes)} ma goc tu bang anh xa gia von.")

    df["product_code"] = df["sellerSku"].apply(lambda s: extract_product_code(s, base_codes_upper))
    df["campaign_flag"] = df["sellerSku"].apply(extract_campaign_flag)
    df["has_gift"] = df["sellerSku"].apply(extract_has_gift)
    df["promo_label"] = df["itemName"].apply(extract_promo_label)

    # -----------------------------------------------------------------------
    # Tự kiểm tra — bắt buộc theo hướng dẫn Bước 3, đừng bỏ qua.
    # -----------------------------------------------------------------------
    print(f"\n% dong rut duoc product_code: {df['product_code'].notna().mean()*100:.1f}%")
    print(f"% dong co campaign_flag:      {df['campaign_flag'].notna().mean()*100:.1f}%")
    print(f"% dong co has_gift = True:    {df['has_gift'].mean()*100:.1f}%")
    print(f"% dong rut duoc promo_label:  {df['promo_label'].notna().mean()*100:.1f}%")

    missing = sorted(df.loc[df["product_code"].isna(), "sellerSku"].unique())
    print(f"\nSo sellerSku KHONG khop duoc ma goc nao: {len(missing)}")
    if missing:
        print("Vi du:", missing[:15])

    print("\nBang cheo product_code x campaign_flag (top 20 theo so dong):")
    cross = (
        df.groupby(["product_code", "campaign_flag"], dropna=False)
        .size()
        .reset_index(name="so_dong")
        .sort_values("so_dong", ascending=False)
    )
    print(cross.head(20).to_string(index=False))

    print("\n>> TODO: tự lướt qua bảng chéo trên và vài ví dụ trong 'missing' để")
    print(">>       xác nhận regex không bắt sai — rồi ghi nhận xét vào")
    print(">>       docs/data_quality.md (mục 11).")

    # itemName đã dùng xong để rút promo_label -> bỏ, tránh lộ tên/thương hiệu.
    df = df.drop(columns=["itemName"])

    out = CLEAN / "orders_parsed.parquet"
    df.to_parquet(out, index=False)
    print(f"\nDa luu: {out}  ({len(df):,} dong x {len(df.columns)} cot)")


if __name__ == "__main__":
    main()
