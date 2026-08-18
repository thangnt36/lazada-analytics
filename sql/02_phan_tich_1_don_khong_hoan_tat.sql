-- Phân tích 1 — Giải phẫu đơn không hoàn tất
-- Chạy trên data/clean/lazada.duckdb (đã dựng ở sql/01_schema.sql)
--
-- QUAN TRỌNG: dùng dim_order_customer / fact_order_item_customer (VIEW), KHÔNG
-- dùng dim_order / fact_order_item (bảng gốc) — bảng gốc còn lẫn 414 đơn vận
-- hành nội bộ (is_bulk_operational, >=20 sản phẩm/đơn), không phải nhu cầu
-- khách hàng thật. Xem docs/data_quality.md mục 14.

-- =============================================================================
-- A. Xu hướng theo tháng: tỷ lệ không hoàn tất và doanh thu thất thoát
--    (tầng ĐƠN — dùng dim_order, không phải fact_order_item, vì is_completed
--    và tỷ lệ % phải đếm trên ĐƠN, không phải trên dòng)
--    doanh_thu_that_thoat dùng total_unit_price (doanh thu sản phẩm thuần),
--    KHÔNG dùng total_paid_price vì đã gồm ship — xem data_quality.md mục 1.
-- =============================================================================
SELECT
    d.year_month,
    COUNT(*) AS tong_don,
    COUNT(*) FILTER (WHERE o.is_completed) AS don_hoan_tat,
    COUNT(*) FILTER (WHERE NOT o.is_completed) AS don_khong_hoan_tat,
    ROUND(100.0 * COUNT(*) FILTER (WHERE NOT o.is_completed) / COUNT(*), 1) AS ty_le_khong_hoan_tat_pct,
    SUM(o.total_unit_price) FILTER (WHERE NOT o.is_completed) AS doanh_thu_that_thoat
FROM dim_order_customer o
JOIN dim_date d ON o.order_date = d.date
GROUP BY d.year_month
ORDER BY d.year_month;

-- =============================================================================
-- B. Phân rã theo buyerFailedDeliveryReason (tầng ĐƠN)
--    Reason nằm ở fact_order_item (tầng dòng) — 1 đơn nhiều dòng cùng reason
--    thì vẫn chỉ tính 1 đơn (DISTINCT orderNumber+shop trước khi đếm).
-- =============================================================================
WITH order_reason AS (
    SELECT DISTINCT orderNumber, shop, buyerFailedDeliveryReason
    FROM fact_order_item_customer
    WHERE NOT is_completed AND buyerFailedDeliveryReason IS NOT NULL
)
SELECT
    r.buyerFailedDeliveryReason,
    COUNT(*) AS so_don,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS ty_le_pct,
    SUM(o.total_unit_price) AS doanh_thu_that_thoat
FROM order_reason r
JOIN dim_order_customer o ON r.orderNumber = o.orderNumber AND r.shop = o.shop
GROUP BY r.buyerFailedDeliveryReason
ORDER BY so_don DESC;

-- =============================================================================
-- C1. Thời gian giao thực tế theo shippingProvider (CHỈ đơn đã giao thành công)
--     Tầng DÒNG vì shippingProvider chưa kiểm chứng có đồng nhất trong 1 đơn hay không.
-- =============================================================================
SELECT
    shippingProvider,
    COUNT(*) AS so_dong,
    ROUND(AVG(DATE_DIFF('day', createTime, deliveredDate)), 1) AS tb_ngay_giao,
    ROUND(MEDIAN(DATE_DIFF('day', createTime, deliveredDate)), 1) AS trung_vi_ngay_giao
FROM fact_order_item_customer
WHERE is_completed AND deliveredDate IS NOT NULL
GROUP BY shippingProvider
ORDER BY tb_ngay_giao DESC;

-- =============================================================================
-- C2. Với riêng lý do "Thời gian giao hàng quá lâu": khách chờ bao lâu (kể từ
--     createTime tới updateTime, tức lúc đơn bị huỷ) trước khi huỷ, và
--     shippingProvider đã được gán hay chưa lúc huỷ.
-- =============================================================================
SELECT
    shippingProvider,
    COUNT(*) AS so_dong,
    ROUND(AVG(DATE_DIFF('day', createTime, updateTime)), 1) AS tb_ngay_cho_truoc_khi_huy
FROM fact_order_item_customer
WHERE NOT is_completed AND buyerFailedDeliveryReason = 'Thời gian giao hàng quá lâu'
GROUP BY shippingProvider
ORDER BY tb_ngay_cho_truoc_khi_huy DESC;

-- =============================================================================
-- D. "Trùng đơn hàng" — thời gian từ lúc đặt tới lúc bị huỷ (updateTime - createTime)
--    GIỚI HẠN: không có khoá khách hàng (đã loại PII ở Bước 1), nên KHÔNG thể
--    tìm ra "đơn song sinh" thật của mỗi đơn trùng để đo khoảng cách giữa 2 đơn
--    như dự tính ban đầu. Đây là proxy khác: đo tốc độ hệ thống/seller phát
--    hiện và xử lý đơn trùng, không phải khoảng cách giữa 2 lần đặt của khách.
-- =============================================================================
SELECT
    COUNT(*) AS so_dong,
    ROUND(AVG(DATE_DIFF('minute', createTime, updateTime)) / 60.0, 1) AS tb_gio_truoc_khi_huy,
    ROUND(MEDIAN(DATE_DIFF('minute', createTime, updateTime)) / 60.0, 1) AS trung_vi_gio,
    COUNT(*) FILTER (WHERE DATE_DIFF('minute', createTime, updateTime) <= 60) AS trong_1h,
    COUNT(*) FILTER (WHERE DATE_DIFF('minute', createTime, updateTime) BETWEEN 61 AND 1440) AS tu_1h_den_1ngay,
    COUNT(*) FILTER (WHERE DATE_DIFF('minute', createTime, updateTime) > 1440) AS tren_1ngay
FROM fact_order_item_customer
WHERE NOT is_completed AND buyerFailedDeliveryReason = 'Trùng đơn hàng';

-- =============================================================================
-- E. "Không hoàn thành thanh toán đúng thời gian" (lý do #1) — payMethod là gì?
-- =============================================================================
WITH order_reason AS (
    SELECT DISTINCT orderNumber, shop
    FROM fact_order_item_customer
    WHERE NOT is_completed
      AND buyerFailedDeliveryReason = 'Không hoàn thành thanh toán đúng thời gian'
)
SELECT o.payMethod, COUNT(*) AS so_don, SUM(o.total_unit_price) AS mat_doanh_thu
FROM order_reason r
JOIN dim_order_customer o ON r.orderNumber = o.orderNumber AND r.shop = o.shop
GROUP BY o.payMethod
ORDER BY so_don DESC;
