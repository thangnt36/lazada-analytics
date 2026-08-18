-- Phân tích 3 — Chi phí thật của COD
-- Chạy trên data/clean/lazada.duckdb
--
-- Dùng dim_order_customer / fact_order_item_customer (đã loại 414 đơn vận
-- hành nội bộ, xem data_quality.md mục 14).
-- Doanh thu thực nhận = unitPrice - sellerDiscountTotal (không trừ
-- platformDiscountTotal — Lazada hoàn riêng, xem mục 15). Không gồm shippingFee
-- (là khoản trung chuyển, không phải doanh thu sản phẩm — xem mục 1).
--
-- payMethod = NULL (khách bỏ ngang trước khi chọn phương thức) bị loại khỏi
-- so sánh COD/Trả trước vì không xác định được ý định thanh toán — xem phần B.

-- =============================================================================
-- A. So sánh COD vs Trả trước — tầng ĐƠN, trên mỗi đơn KHỞI TẠO (kể cả huỷ)
-- =============================================================================
WITH order_revenue AS (
    SELECT
        o.orderNumber,
        o.shop,
        o.payMethod,
        o.is_completed,
        SUM(f.unitPrice - f.sellerDiscountTotal) AS doanh_thu_don
    FROM dim_order_customer o
    JOIN fact_order_item_customer f ON o.orderNumber = f.orderNumber AND o.shop = f.shop
    WHERE o.payMethod IS NOT NULL
    GROUP BY o.orderNumber, o.shop, o.payMethod, o.is_completed
)
SELECT
    CASE WHEN payMethod = 'COD' THEN 'COD' ELSE 'Tra truoc' END AS nhom_thanh_toan,
    COUNT(*) AS so_don_khoi_tao,
    ROUND(100.0 * (1 - AVG(is_completed::INT)), 1) AS ty_le_huy_pct,
    ROUND(AVG(doanh_thu_don) FILTER (WHERE is_completed), 0) AS doanh_thu_tb_moi_don_hoan_tat,
    -- Mau so la TAT CA don khoi tao, tu so chi cong doanh thu cua don DA HOAN
    -- TAT -> phan anh dung "doanh thu thuc nhan tren moi don khoi tao"
    ROUND(SUM(CASE WHEN is_completed THEN doanh_thu_don ELSE 0 END) / COUNT(*), 0) AS doanh_thu_tb_moi_don_khoi_tao
FROM order_revenue
GROUP BY 1;

-- =============================================================================
-- B. Đối chiếu quy mô: COD chiếm bao nhiêu % trong số đơn ĐÃ XÁC ĐỊNH phương
--    thức thanh toán (loại nhóm payMethod = NULL, tức bỏ ngang trước khi chọn)
-- =============================================================================
SELECT
    CASE WHEN payMethod = 'COD' THEN 'COD'
         WHEN payMethod IS NULL THEN 'Chua xac dinh (bo ngang checkout)'
         ELSE 'Tra truoc' END AS nhom_thanh_toan,
    COUNT(*) AS so_don,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS ty_le_pct
FROM dim_order_customer
GROUP BY 1
ORDER BY so_don DESC;
