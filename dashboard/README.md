# Superset qua Docker — Bước 5

## Điều kiện: Docker Desktop đã cài và đang chạy

Cài tại https://www.docker.com/products/docker-desktop/ (bản Windows dùng
backend WSL2 — Docker Desktop tự hỏi cài nếu máy chưa có). Có thể cần khởi
động lại máy sau khi cài. Sau khi cài xong, mở Docker Desktop, đợi biểu tượng
báo "Running" rồi mới chạy các lệnh dưới.

## Chạy Superset

```
cd dashboard
docker compose up -d --build
```

Lần đầu build sẽ mất vài phút (tải image `apache/superset` ~1-2GB). Sau khi
container chạy, khởi tạo Superset (chỉ cần làm 1 lần):

```
docker compose exec superset superset db upgrade
docker compose exec superset superset fab create-admin --username admin --firstname Admin --lastname User --email admin@local --password admin
docker compose exec superset superset init
```

Mở trình duyệt: http://localhost:8088 — đăng nhập `admin` / `admin` (đổi mật
khẩu nếu định public dashboard sau này).

## Kết nối DuckDB

Trong Superset: **Settings → Database Connections → + Database → Other**,
SQLAlchemy URI:

```
duckdb:////app/data/lazada.duckdb
```

(4 dấu `/` — 3 dấu chuẩn của URI + 1 dấu cho đường dẫn tuyệt đối trong
container). File `lazada.duckdb` được mount từ `data/clean/` ở ngoài vào
`/app/data/` trong container qua `docker-compose.yml`.

## Dừng / dọn dẹp

```
docker compose down          # dừng, giữ lại dữ liệu Superset (dashboard đã tạo)
docker compose down -v       # dừng và xoá luôn dữ liệu Superset (làm lại từ đầu)
```

## 3 trang cần dựng

- **Kinh doanh** — doanh thu theo tháng, AOV, lãi gộp/biên, cơ cấu doanh thu gộp → chiết khấu → phí ship → thực nhận
- **Sản phẩm** — Pareto doanh thu theo `product_code`, so xếp hạng doanh thu với xếp hạng lợi nhuận, tỷ lệ huỷ theo SKU
- **Vận hành** — tỷ lệ hoàn tất/huỷ/hoàn theo tháng, doanh thu thất thoát, `buyerFailedDeliveryReason`, thời gian giao theo `shippingProvider`, tỷ lệ huỷ theo `payMethod`

Nhớ dùng `dim_order_customer`/`fact_order_item_customer` (đã loại đơn ảo, xem
`docs/data_quality.md` mục 14) khi tạo dataset/chart trong Superset — nếu
dùng thẳng `dim_order`/`fact_order_item` gốc, số liệu sẽ lệch giống lỗi đã sửa
ở Phân tích 1 và 2.
