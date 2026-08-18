-- Phân tích 2 — Flash sale có thật sự lãi không?
-- Chạy trên data/clean/lazada.duckdb
--
-- Dùng dim_order_customer / fact_order_item_customer (đã loại 414 đơn vận
-- hành nội bộ >=20 sản phẩm/đơn) — bắt buộc, xem docs/data_quality.md mục 14.
-- So sánh campaign_flag (Flash Sale) vs không (Thường) TRÊN CÙNG product_code
-- để kiểm soát yếu tố "sản phẩm khác nhau vốn đã khác lãi suất".
--
-- CÔNG THỨC LÃI GỘP: unitPrice - sellerDiscountTotal - gia_nhap
-- KHÔNG trừ platformDiscountTotal — Lazada hoàn riêng phần này cho seller qua
-- đối soát, không làm giảm lãi thực nhận của shop. unitPrice là giá NIÊM YẾT
-- (trước discount), không phải giá thực trả — xác nhận trên 8.611 dòng có
-- discount: paidPrice = unitPrice + shippingFee - sellerDiscountTotal -
-- platformDiscountTotal khớp 100%. Xem docs/data_quality.md mục 1 và 15.
--
-- Lưu ý: nhóm product_code kiểu CT/CTFS (campaign đã dính vào chính mã gốc,
-- xem data_quality.md mục 11) KHÔNG nằm trong so sánh này — vì với các mã đó,
-- không tồn tại hàng "Thường" cùng product_code để so.

-- =============================================================================
-- A. So sánh theo từng product_code (chỉ lấy sản phẩm có >=20 dòng mỗi nhóm
--    để đủ mẫu, và có giá vốn để tính lãi gộp)
-- =============================================================================
WITH item_margin AS (
    SELECT
        f.*,
        p.gia_nhap,
        CASE WHEN f.campaign_flag IS NOT NULL THEN 'Flash Sale' ELSE 'Thuong' END AS nhom,
        (f.unitPrice - f.sellerDiscountTotal - p.gia_nhap) AS bien_don_vi
    FROM fact_order_item_customer f
    JOIN dim_product p ON f.product_code = p.product_code
    WHERE p.gia_nhap IS NOT NULL
),
eligible AS (
    SELECT product_code
    FROM item_margin
    GROUP BY product_code
    HAVING COUNT(*) FILTER (WHERE nhom = 'Flash Sale') >= 20
       AND COUNT(*) FILTER (WHERE nhom = 'Thuong') >= 20
)
SELECT
    im.product_code,
    im.nhom,
    COUNT(*) AS so_don_khoi_tao,
    ROUND(100.0 * (1 - AVG(im.is_completed::INT)), 1) AS ty_le_huy_pct,
    ROUND(AVG(im.sellerDiscountTotal), 0) AS seller_discount_tb,
    ROUND(AVG(im.unitPrice), 0) AS gia_niem_yet_tb,
    -- Mau so la TAT CA don khoi tao (ke ca huy), tu so chi cong lai gop cua
    -- don DA HOAN TAT -> phan anh dung "lai gop thuc nhan tren moi lan khoi tao"
    ROUND(SUM(CASE WHEN im.is_completed THEN im.bien_don_vi ELSE 0 END) / COUNT(*), 0) AS lai_gop_tb_moi_don_khoi_tao
FROM item_margin im
JOIN eligible ep ON im.product_code = ep.product_code
GROUP BY im.product_code, im.nhom
ORDER BY im.product_code, im.nhom;

-- =============================================================================
-- B. SHRTT01 — sản phẩm chủ lực (~55% khối lượng của tập đủ mẫu ở phần A).
--    Đây là bằng chứng chính của kết luận, vì các sản phẩm còn lại mẫu nhỏ và
--    đóng góp doanh số không đáng kể (theo xác nhận của người vận hành).
-- =============================================================================
WITH item_margin AS (
    SELECT
        f.*,
        p.gia_nhap,
        CASE WHEN f.campaign_flag IS NOT NULL THEN 'Flash Sale' ELSE 'Thuong' END AS nhom,
        (f.unitPrice - f.sellerDiscountTotal - p.gia_nhap) AS bien_don_vi
    FROM fact_order_item_customer f
    JOIN dim_product p ON f.product_code = p.product_code
    WHERE p.gia_nhap IS NOT NULL AND f.product_code = 'SHRTT01'
)
SELECT
    nhom,
    COUNT(*) AS so_don_khoi_tao,
    ROUND(100.0 * (1 - AVG(is_completed::INT)), 1) AS ty_le_huy_pct,
    ROUND(AVG(sellerDiscountTotal), 0) AS seller_discount_tb,
    ROUND(AVG(unitPrice), 0) AS gia_niem_yet_tb,
    ROUND(AVG(gia_nhap), 0) AS gia_von_tb,
    ROUND(SUM(CASE WHEN is_completed THEN bien_don_vi ELSE 0 END) / COUNT(*), 0) AS lai_gop_tb_moi_don_khoi_tao
FROM item_margin
GROUP BY nhom;

-- =============================================================================
-- C. Tổng hợp gộp (pooled) trên toàn bộ 16 sản phẩm đủ điều kiện — BỐI CẢNH
--    PHỤ, không phải kết luận chính. Bị chi phối bởi vài sản phẩm mẫu nhỏ có
--    lãi gộp/đơn vị rất cao (ít dữ liệu, ít đại diện) — xem phần A để soi
--    từng sản phẩm trước khi tin số gộp này.
-- =============================================================================
WITH item_margin AS (
    SELECT
        f.*,
        p.gia_nhap,
        CASE WHEN f.campaign_flag IS NOT NULL THEN 'Flash Sale' ELSE 'Thuong' END AS nhom,
        (f.unitPrice - f.sellerDiscountTotal - p.gia_nhap) AS bien_don_vi
    FROM fact_order_item_customer f
    JOIN dim_product p ON f.product_code = p.product_code
    WHERE p.gia_nhap IS NOT NULL
),
eligible AS (
    SELECT product_code
    FROM item_margin
    GROUP BY product_code
    HAVING COUNT(*) FILTER (WHERE nhom = 'Flash Sale') >= 20
       AND COUNT(*) FILTER (WHERE nhom = 'Thuong') >= 20
)
SELECT
    im.nhom,
    COUNT(*) AS so_don_khoi_tao,
    ROUND(100.0 * (1 - AVG(im.is_completed::INT)), 1) AS ty_le_huy_pct,
    ROUND(AVG(im.sellerDiscountTotal), 0) AS seller_discount_tb,
    ROUND(AVG(im.unitPrice), 0) AS gia_niem_yet_tb,
    ROUND(SUM(CASE WHEN im.is_completed THEN im.bien_don_vi ELSE 0 END) / COUNT(*), 0) AS lai_gop_tb_moi_don_khoi_tao,
    ROUND(SUM(CASE WHEN im.is_completed THEN im.bien_don_vi ELSE 0 END), 0) AS tong_lai_gop_thuc_nhan
FROM item_margin im
JOIN eligible ep ON im.product_code = ep.product_code
GROUP BY im.nhom;
