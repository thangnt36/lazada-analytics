-- 01_schema.sql — Bước 4: mô hình dữ liệu (star schema) trong DuckDB.
--
-- Fact table:  fact_order_item  — grain = 1 dòng = 1 orderItemId (1 lần mua 1
--              sellerSku trong 1 đơn). Đây là mức chi tiết thấp nhất có trong
--              dữ liệu (không có cột quantity — số lượng thể hiện bằng số dòng).
--              Chứa các số đo cộng dồn được: unitPrice, paidPrice, shippingFee,
--              sellerDiscountTotal, platformDiscountTotal, bundleDiscount.
--
-- Dimension:   dim_order, dim_product, dim_date, dim_shipping_provider — mô tả
--              ngữ cảnh (who/what/when), không phải luồng sự kiện đo lường riêng.
--
-- Khoá dim_order là (orderNumber, shop), KHÔNG phải orderNumber một mình:
-- phát hiện 6 orderNumber trùng giữa Chetanic và Lumytive, cùng createTime —
-- khách mua chung giỏ hàng từ 2 shop trong 1 lượt thanh toán, Lazada gán chung
-- orderNumber cấp giỏ hàng. Gộp theo orderNumber một mình sẽ trộn nhầm doanh
-- thu 2 shop khác nhau vào 1 dòng. Xem docs/data_quality.md mục 12.
--
-- shippingProvider có lỗi case ("Vinacapital" / "vinacapital" là cùng 1 hãng)
-- — chuẩn hoá về "Vinacapital" trước khi dùng làm khoá dim.

-- ---------------------------------------------------------------------------
-- fact_order_item — khoá: orderItemId
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE fact_order_item AS
SELECT
    orderItemId,
    orderNumber,
    shop,
    product_code,
    campaign_flag,
    has_gift,
    promo_label,
    status,
    is_completed,
    unitPrice,
    paidPrice,
    shippingFee,
    sellerDiscountTotal,
    platformDiscountTotal,
    bundleDiscount,
    CASE WHEN LOWER(TRIM(shippingProvider)) = 'vinacapital' THEN 'Vinacapital'
         ELSE shippingProvider END AS shippingProvider,
    shippingProviderType,
    buyerFailedDeliveryReason,
    buyerFailedDeliveryDetail,
    CAST(createTime AS DATE) AS order_date,
    createTime,
    updateTime,
    deliveredDate,
    promisedShippingTime
FROM read_parquet('data/clean/orders_parsed.parquet');

-- ---------------------------------------------------------------------------
-- dim_order — khoá: (orderNumber, shop), tổng hợp từ fact_order_item
-- is_completed ở tầng đơn = TRUE chỉ khi TOÀN BỘ dòng trong đơn đều hoàn tất
-- (hoàn 1 phần vẫn tính là đơn không hoàn tất, vì shop vẫn mất doanh thu phần đó).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_order AS
SELECT
    orderNumber,
    shop,
    ANY_VALUE(payMethod) AS payMethod,
    MIN(createTime) AS order_created_at,
    CAST(MIN(createTime) AS DATE) AS order_date,
    COUNT(*) AS n_items,
    SUM(is_completed::INT) AS n_items_completed,
    BOOL_AND(is_completed) AS is_completed,
    SUM(unitPrice) AS total_unit_price,
    SUM(paidPrice) AS total_paid_price,
    SUM(shippingFee) AS total_shipping_fee,
    SUM(sellerDiscountTotal) AS total_seller_discount,
    SUM(platformDiscountTotal) AS total_platform_discount,
    -- >=20 san pham/don la don van hanh noi bo (dung de tao FOMO slot flash
    -- sale roi tu huy), khong phai nhu cau khach hang that. Nguong xac dinh
    -- bang khoang trong tu nhien trong phan bo n_items (16 -> 20, khong don
    -- nao co 17/19 sp). Xem docs/data_quality.md muc 14.
    (COUNT(*) >= 20) AS is_bulk_operational
FROM read_parquet('data/clean/orders_parsed.parquet')
GROUP BY orderNumber, shop;

-- View dung cho MOI phan tich hanh vi khach hang tu day ve sau — da loai cum
-- don van hanh noi bo. Khong dung dim_order/fact_order_item goc truc tiep
-- cho cac cau hoi ve khach hang nua.
CREATE OR REPLACE VIEW dim_order_customer AS
SELECT * EXCLUDE (is_bulk_operational)
FROM dim_order
WHERE NOT is_bulk_operational;

CREATE OR REPLACE VIEW fact_order_item_customer AS
SELECT f.*
FROM fact_order_item f
JOIN dim_order_customer o ON f.orderNumber = o.orderNumber AND f.shop = o.shop;

-- ---------------------------------------------------------------------------
-- dim_product — khoá: product_code
-- LEFT JOIN với sku_mapping.csv để giữ đủ 196 mã (kể cả 38 mã chưa có giá
-- vốn -> gia_nhap = NULL, không bịa số). Cột tên sản phẩm/tên trong file giá
-- vốn KHÔNG đưa vào đây — lộ thương hiệu, cùng lý do itemName đã bị loại ở
-- Bước 1.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_product AS
SELECT
    f.product_code,
    m.gia_nhap
FROM (SELECT DISTINCT product_code FROM read_parquet('data/clean/orders_parsed.parquet')) f
LEFT JOIN read_csv_auto('data/clean/sku_mapping.csv') m
    ON f.product_code = m.product_code;

-- ---------------------------------------------------------------------------
-- dim_date — 1 dòng/ngày, phủ trọn khung thời gian dữ liệu (12/2020 – 01/2023)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_date AS
SELECT
    d::DATE AS date,
    YEAR(d) AS year,
    MONTH(d) AS month,
    QUARTER(d) AS quarter,
    STRFTIME(d, '%Y-%m') AS year_month,
    DAYOFWEEK(d) AS day_of_week
FROM generate_series(
    (SELECT MIN(CAST(createTime AS DATE)) FROM read_parquet('data/clean/orders_parsed.parquet')),
    (SELECT MAX(CAST(createTime AS DATE)) FROM read_parquet('data/clean/orders_parsed.parquet')),
    INTERVAL 1 DAY
) AS t(d);

-- ---------------------------------------------------------------------------
-- dim_shipping_provider — khoá: shippingProvider (đã chuẩn hoá case ở fact)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_shipping_provider AS
SELECT DISTINCT
    shippingProvider,
    shippingProviderType
FROM fact_order_item
WHERE shippingProvider IS NOT NULL;
