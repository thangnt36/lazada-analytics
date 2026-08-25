# Nhật ký chất lượng dữ liệu

Ghi lại mọi bất thường gặp phải trong quá trình làm sạch và xử lý dữ liệu, cùng
quyết định xử lý và lý do. Mục này bê thẳng vào README ở Bước 7 — viết như thể
người đọc không chạy code, chỉ đọc file này.

Mỗi mục theo khung: **Vấn đề → Bằng chứng → Xử lý → Ảnh hưởng tới phân tích sau**.

---

## 1. paidPrice tính ở tầng dòng hay tầng đơn?

**Vấn đề:** Không rõ `paidPrice` là giá của cả đơn hay giá riêng từng dòng
(order item). Sai chỗ này thì mọi con số doanh thu/AOV sau đều lệch.

**Bằng chứng:** Đơn mẫu `267958870697374` có 5 dòng:

| sellerSku | unitPrice | paidPrice | shippingFee |
|---|---|---|---|
| QT3D-Màu xám | 75.000 | 78.000 | 3.000 |
| DGKI01-100 | 59.000 | 62.000 | 3.000 |
| SRHX01-60 | 69.000 | 70.500 | 1.500 |
| SHR01-Set A | 54.000 | 55.500 | 1.500 |
| SHR01-Set B | 54.000 | 55.500 | 1.500 |

Mỗi dòng: `paidPrice = unitPrice + shippingFee` khớp chính xác.

**Xử lý:** Đối chiếu với thông tin thanh toán thật của đơn `267958870697374`
trên Lazada:

| | Lazada ghi | Cộng dồn 5 dòng trong data |
|---|---|---|
| Tổng tiền (giá gốc) | 311.000₫ | `SUM(unitPrice)` = 311.000 |
| Phí vận chuyển | 10.500₫ | `SUM(shippingFee)` = 10.500 |
| Tổng cộng khách trả | 321.500₫ | `SUM(paidPrice)` = 321.500 |

Khớp tuyệt đối cả 3 số. **Kết luận: `paidPrice` là giá trị theo DÒNG** —
`unitPrice` và `shippingFee` đã được phân bổ (allocate) cho từng dòng, không
phải một khoản duy nhất lặp lại ở mọi dòng của đơn. Cộng dồn `paidPrice` theo
`orderNumber` cho ra đúng số tiền thật khách đã trả.

**⚠️ CẬP NHẬT (Phân tích 2, khi tính lãi gộp flash sale):** đơn mẫu ở trên
tình cờ **không có discount** (`sellerDiscountTotal = platformDiscountTotal =
0`), nên công thức `paidPrice = unitPrice + shippingFee` chỉ là TRƯỜNG HỢP
RIÊNG. Kiểm tra lại trên 8.611 dòng CÓ discount thật (`sellerDiscountTotal > 0
OR platformDiscountTotal > 0`), công thức đúng và khớp 100% là:

```
paidPrice = unitPrice + shippingFee - sellerDiscountTotal - platformDiscountTotal
```

**Kết luận đúng: `unitPrice` là giá NIÊM YẾT (trước discount), không phải giá
thực trả.** Điều này quan trọng vì mã flash sale luôn có `unitPrice` niêm yết
cao hơn hẳn hàng thường (do yêu cầu giảm sâu để đăng ký slot của Lazada) — nếu
dùng thẳng `unitPrice` làm "giá bán"/"doanh thu" mà không trừ discount, mọi so
sánh liên quan tới sản phẩm có chạy khuyến mãi sẽ bị thổi phồng.

**Ảnh hưởng:** Doanh thu sản phẩm (giá bán thuần, đã trừ discount) → dùng
`SUM(unitPrice - sellerDiscountTotal - platformDiscountTotal)`, không phải
`SUM(unitPrice)` một mình — xem thêm mục 15 về cách quyết toán 2 loại discount
khác nhau. Doanh thu thực nhận từ khách (gồm cả ship) → dùng `SUM(paidPrice)`,
gọi đúng tên "thực thu gồm ship", đừng gọi nhầm là doanh thu sản phẩm. AOV ở
tầng đơn = `SUM(paidPrice)` GROUP BY `orderNumber`, không phải trung bình theo
dòng.

---

## 15. sellerDiscountTotal vs platformDiscountTotal — ai thực sự trả cho phần giảm giá

**Vấn đề:** Có 2 cột discount tách riêng. Cả 2 đều làm khách trả ít hơn (đã
xác nhận ở mục 1: `paidPrice` trừ cả 2 cột). Nhưng **lãi gộp thực nhận của
seller** thì không nhất thiết bị trừ cả 2 — phụ thuộc ai tài trợ khoản giảm.

**Xử lý (xác nhận từ người vận hành thực tế):** `platformDiscountTotal` do
Lazada tài trợ — Lazada hoàn lại riêng phần này cho seller qua đối soát, không
làm giảm doanh thu seller thực nhận. `sellerDiscountTotal` do chính shop chịu
— trừ thẳng vào doanh thu thực nhận.

```
Doanh thu seller thực nhận (chưa trừ giá vốn) = unitPrice - sellerDiscountTotal
Lãi gộp / đơn vị = (unitPrice - sellerDiscountTotal) - gia_nhap
```

**Ảnh hưởng:** Công thức lãi gộp ban đầu ở Phân tích 2
(`unitPrice - gia_nhap`, bỏ qua cả 2 loại discount) bị thổi phồng — sản phẩm
discount càng nhiều (đặc biệt hàng flash sale) càng bị lệch nặng. Đã sửa lại
theo công thức đúng ở trên, xem `sql/03_phan_tich_2_flash_sale.sql`. Doanh thu
tính ở Phân tích 1 dùng `SUM(unitPrice)` (chưa trừ `sellerDiscountTotal`) —
đây là ước lượng hơi cao hơn doanh thu thực nhận thật, nhưng `sellerDiscountTotal`
nhìn chung nhỏ hơn nhiều so với quy mô sai số đã sửa ở mục 14 (cụm đơn ảo) nên
chưa tính lại — cần nêu rõ trong mục giới hạn của Phân tích 1 khi viết README.

---

## 2. Khung thời gian hai shop lệch nhau

**Vấn đề:** Hai file không cùng khoảng thời gian.

**Bằng chứng:** Chetanic: 12/2020 – 11/2022 (32.452 dòng, 13.579 đơn).
Lumytive: 01/2021 – 01/2023 (1.184 dòng, 751 đơn). Khung thời gian gộp thật là
12/2020 – 01/2023, không phải 2021–2022.

**Xử lý:** Giữ nguyên, gộp theo cột `shop` để phân biệt khi cần so sánh riêng
từng gian hàng.

**Ảnh hưởng:** Mọi phân tích theo tháng ở rìa hai đầu (12/2020, 02/2023 trở đi)
chỉ có dữ liệu của một shop — cần chú thích khi vẽ biểu đồ theo thời gian.

---

## 3. Cột rỗng gần như hoàn toàn — nhưng không phải cột nào cũng rỗng 100%

**Vấn đề:** 4 cột nghi ngờ rỗng gần hết: `wareHouse`, `walletCredit`,
`bundleDiscount`, `refundAmount`.

**Bằng chứng:** Chạy `df.isna().mean()` trên dữ liệu gốc (33.636 dòng):

| Cột | % rỗng | Số dòng có giá trị thật |
|---|---|---|
| `wareHouse` | 100,0% | 0 |
| `walletCredit` | 100,0% | 0 |
| `refundAmount` | 100,0% | 0 |
| `bundleDiscount` | 99,1% | **286** (vd. 250, 250, 250, 411₫) |

`bundleDiscount` mang ý nghĩa "phí khuyến mãi gói sản phẩm" — hiếm gặp (0,9%
dòng) nhưng là dữ liệu thật, không phải nhiễu.

**Xử lý:** `wareHouse`, `walletCredit`, `refundAmount` → loại khỏi bản clean
(đúng như giả định ban đầu, rỗng 100%). `bundleDiscount` → **giữ lại**,
`fillna(0)` thay vì drop. Đã sửa `EMPTY_COLS` trong `01_clean.py` để bỏ
`bundleDiscount` ra khỏi danh sách loại bỏ.

**Ảnh hưởng:** `wareHouse`/`walletCredit`/`refundAmount` không dùng được cho
bất kỳ phân tích nào — nêu rõ trong mục giới hạn của báo cáo. `bundleDiscount`
có thể dùng làm tín hiệu phụ cho các đơn có chương trình combo/gói quà, dù mẫu
rất nhỏ (286/33.636 dòng) nên không đủ để phân tích riêng, chỉ nên nhắc tới
như một quan sát phụ.

---

## 4. sellerDiscountTotal / platformDiscountTotal mang giá trị âm

**Vấn đề:** Hai cột chiết khấu lưu giá trị âm trong file gốc thay vì dương.

**Bằng chứng:** Xem vài dòng gốc trước khi `.abs()`: mọi giá trị khác 0 của hai
cột này đều mang dấu âm — đúng bản chất là "discount", không phải lỗi đọc file
hay lỗi kiểu dữ liệu.

**Xử lý:** Đổi về dương bằng `.abs()` trong `01_clean.py` để cộng dồn cho dễ.

**Ảnh hưởng:** Nếu tính "doanh thu ròng sau chiết khấu" = doanh thu gộp −
discount, nhớ là discount trong bản clean đã dương sẵn (trừ, không cộng).

---

## 5. Trạng thái đơn — 47,1% dòng không hoàn tất

**Vấn đề:** Gần một nửa số dòng không phải đơn thành công.

**Bằng chứng:**

```
confirmed                        17.785   52,9%
canceled                         14.592   43,4%
Package Returned                    710    2,1%
In Transit: Returning to seller     536    1,6%
Lost by 3PL                          11    0,0%
delivered                             1    0,0%
returned                              1    0,0%
```

**Xử lý:** Cột `is_completed` = True chỉ cho `confirmed` và `delivered`
(xem `01_clean.py`).

**Ảnh hưởng:** Đây là phát hiện chủ lực của Phân tích 1 (Bước 6). Mọi tỷ lệ
huỷ/hoàn phải tính trên **tổng đơn khởi tạo**, không phải trên đơn hoàn tất —
đây là lỗi mẫu số dễ mắc nhất trong toàn bộ project.

---

## 6. Lỗi dấu tiếng Việt ngay trong SKU

**Vấn đề:** Cùng một sản phẩm nhưng SKU khác nhau chỉ vì lỗi gõ dấu.

**Bằng chứng:** Tồn tại cả `SHRTT01-1 Set 3 mau` lẫn `SHRTT01-1 Set 3 màu`.

**Xử lý:** Gộp thành một `product_code` duy nhất khi tách SKU ở Bước 3
(`02_parse_sku.py`) — coi `SHRTT01-1 Set 3 mau` và `SHRTT01-1 Set 3 màu` là
cùng một sản phẩm.

**Ảnh hưởng:** Nếu không gộp, Pareto doanh thu theo SKU sẽ bị chia nhỏ sai —
sản phẩm này trông kém hơn thực tế.

---

## 7. sellerSku không khớp bảng giá vốn

**Vấn đề:** 457 `sellerSku` không có cột mã nào chung với file giá vốn (chỉ có
tên sản phẩm dạng chữ tự do).

**Bằng chứng:** 457 `sellerSku` rút gọn còn 196 mã gốc. Chủ shop tạo mã mới mỗi
khi chạy khuyến mãi hoặc mở gian hàng thứ hai.

**Xử lý:** Ánh xạ bằng tay qua `Bang_anh_xa_SKU_giavon.xlsx` (Bước 2). Kế hoạch
ban đầu là dừng ở mốc 85–90% doanh thu (~24–34 mã) — thực tế đã điền **158/196
mã (80,6% số mã), phủ 100% doanh thu luỹ kế** (xem mục 10). Xuất ra
`data/clean/sku_mapping.csv`.

**Ảnh hưởng:** Giá vốn/lãi gộp phủ 100% doanh thu, không còn giới hạn 85–90%
như dự tính ban đầu — mục "giới hạn phân tích" ở Bước 6 cần cập nhật lại theo
số liệu thật này, không chép nguyên câu cũ trong hướng dẫn.

---

## 8. Cột "Đã bán" trong file giá vốn là đa kênh, không phải riêng Lazada

**Vấn đề:** File giá vốn có cột "Đã bán" tính trên mọi kênh bán, còn dữ liệu
đơn hàng ở đây chỉ có Lazada.

**Xử lý:** Chỉ lấy cột **giá nhập** từ file giá vốn, không đối chiếu số lượng
bán.

**Ảnh hưởng:** Không được dùng "Đã bán" để kiểm tra chéo số lượng bán Lazada —
hai số không đo cùng một thứ.

---

## 9. Một orderNumber có nhiều orderItemId

**Vấn đề:** Không có cột số lượng (quantity) — số lượng mua thể hiện bằng số
dòng.

**Xử lý:** Mọi phân tích ở tầng sản phẩm/doanh thu dùng tầng item (mỗi dòng);
tầng đơn (AOV, số đơn) phải `GROUP BY orderNumber` trước.

**Ảnh hưởng:** 33.636 dòng ↔ 14.324 đơn — chọn sai tầng là lỗi phổ biến nhất
trong dự án này (xem "Ba chỗ dễ sai nhất").

---

## 10. Độ phủ ánh xạ SKU vượt xa mốc khuyến nghị (85–90% → 100%)

**Vấn đề:** Hướng dẫn Bước 2 đề nghị dừng điền khi luỹ kế doanh thu chạm
85–90% (ước tính 24–34 mã), để tránh mất thời gian ánh xạ những mã đóng góp
doanh thu quá nhỏ. Thực tế đã điền hết 158/196 mã, phủ 100% doanh thu luỹ kế.

**Bằng chứng:** `sku_mapping.csv` có 158 dòng, cột `luy_ke_pct` chạy tới
100,0%. 38 mã còn lại không điền (đã để trống thay vì đoán, theo đúng nguyên
tắc "không chắc thì để trống").

**Xử lý:** Giữ nguyên 158 dòng đã điền — không cắt bớt về mốc 85–90% cho khớp
kế hoạch ban đầu, vì độ phủ cao hơn chỉ có lợi cho phân tích, miễn là từng
dòng đã điền đều có căn cứ (tên sản phẩm khớp), không phải đoán đại.

**Ảnh hưởng:** Con số kế hoạch ban đầu "giá vốn chỉ phủ 85–90% doanh thu"
**không còn đúng** — cần sửa lại theo số liệu thật (phủ gần như toàn bộ
doanh thu, phần thiếu chỉ nằm ở 38 mã đuôi dài doanh thu rất nhỏ). Đây là
điểm cần lưu ý khi viết README: đối chiếu con số dự kiến ban đầu với con số
thật đã làm, đừng bê nguyên số cũ.

---

## 11. Hậu tố chiến dịch không đồng nhất — cả về cách viết lẫn độ chi tiết của mã gốc

**Vấn đề:** Hai giả định ban đầu ở Bước 3 đều sai khi đối chiếu với dữ liệu thật.

**Bằng chứng — (a) hậu tố không sạch:** Ngoài dạng `-FS` như tài liệu mô tả, còn
tồn tại dạng dính liền không có dấu gạch ngang: `CTFS`, `CTFS2`, `CTFS3`,
`TXFS`, `TXFS2`, `TXFS3`, `HRMN-coolFS`, `HRMN-warmFS`,
`KCKDHS01-tunhienFS`/`FS2`, `SV01-Set 5 màu FS`/`FS2`/`FS3`, `S5SFS2`, và các
biến thể có khoảng trắng quanh dấu gạch (`Fresh & Clean - FS`,
`Beach Flower - FS`). Tương tự với `SL` (`CTSL`, `CTSL2`, `HRMN-coolSL`...).

**Bằng chứng — (b) độ chi tiết mã gốc không đồng nhất:** Trong
`Bang_anh_xa_SKU_giavon.xlsx`, nhóm tiền tố `CT` liệt kê `CTFS`, `CTFS2`,
`CTFS3`, `CTSL`, `CTSL2` như các **mã gốc riêng biệt**, ngang hàng với `CT`,
`CT02`, `CT03` — tức là ở nhóm này, hậu tố campaign đã được coi là một phần
của mã sản phẩm, không phải cờ tách rời. Trong khi đó nhóm `HRMN`, `SHRTT01`
chỉ có mã gốc dạng tiền tố (`HRMN`, `HRMN01`, `HRMN02`, `SHRTT01`), campaign
nằm ở phần đuôi bị cắt bỏ khi quy về mã gốc.

**Xử lý:**
- `campaign_flag`/`has_gift` dùng regex khớp CUỐI chuỗi (`FS([23])?$`,
  `SL([23])?$`, `(\d)?stickera?$`), case-insensitive, không yêu cầu dấu `-`
  đứng trước — bắt được cả dạng dính liền.
- `product_code` khớp theo **mã gốc dài nhất làm prefix** của `sellerSku`
  (case-insensitive), giữ nguyên đúng độ chi tiết mà bảng ánh xạ giá vốn đã
  chọn cho từng dòng sản phẩm — không tự strip suffix thêm. Nhờ vậy `CTFS` vẫn
  là chính nó (khớp giá vốn của "CTFS"), còn `SHRTT01-...-FS2` vẫn rút đúng về
  `SHRTT01` (khớp giá vốn của "SHRTT01"), dù campaign đã được strip ra cột
  `campaign_flag` riêng.
- Kết quả chạy `02_parse_sku.py`: 100% dòng rút được `product_code` (196/196
  mã gốc đều dùng tới, không mã nào bị bỏ sót), 0 `sellerSku` không khớp được
  mã nào. `campaign_flag` có ở 29,3% dòng, `has_gift=True` ở 19,1% dòng,
  `promo_label` rút được ở 100% dòng (đã soát bằng mắt 50 nhãn khác nhau, toàn
  bộ đều là nhãn khuyến mãi hợp lý, không có nhiễu).

**Ảnh hưởng:** Vì `product_code` được giữ ở đúng độ chi tiết của bảng giá vốn
(có thể đã gộp sẵn campaign vào một số mã như `CTFS`), khi làm Phân tích 2
("Flash sale có thật sự lãi không?") cần lưu ý: so sánh nhóm flash sale với
nhóm thường **trên cùng `product_code`** sẽ tự động loại các sản phẩm mà
`product_code` đã gộp campaign vào mã (như `CTFS`) ra khỏi phép so sánh nội bộ
sản phẩm đó — không sao, vì với nhóm này flash sale và hàng thường vốn dĩ đã
là hai `product_code` khác nhau ngay từ đầu (do chính người vận hành đặt mã
như vậy), không cần cột `campaign_flag` để tách nữa.

---

## 12. orderNumber không phải khoá duy nhất giữa 2 shop

**Vấn đề:** 6 `orderNumber` xuất hiện ở CẢ Chetanic lẫn Lumytive, cùng
`createTime` tuyệt đối. Nếu `GROUP BY orderNumber` một mình khi dựng
`dim_order`, 2 đơn của 2 shop khác nhau sẽ bị gộp nhầm thành 1 dòng, trộn lẫn
doanh thu.

**Bằng chứng:** Vd. `orderNumber = 282398891374195` lúc `2021-04-19 07:06:00`:
một phần dòng có `sellerSku = SRHX01-mamoi, shop = Chetanic`, phần còn lại
`sellerSku = KCKDHS-Tangmocdan, shop = Lumytive` — cùng giờ phút giây tuyệt
đối. Tổng 6 trường hợp, tất cả rơi vào 03/04/2021 và 19/04/2021.

**Xử lý:** Xác nhận đây là hành vi thật của Lazada — khi khách mua sản phẩm từ
nhiều shop trong cùng một lượt thanh toán (giỏ hàng gộp nhiều seller), nền
tảng gán chung một `orderNumber` cấp giỏ hàng cho cả hai shop, dù mỗi shop chỉ
thấy phần đơn hàng của mình. `dim_order` dùng khoá kép **(orderNumber, shop)**
thay vì `orderNumber` một mình. Số đơn thực tế: **14.330**, không phải 14.324
như con số ban đầu ghi nhận (con số cũ đếm theo `orderNumber` đơn lẻ, chưa
tính giao nhau giữa 2 shop).

**Ảnh hưởng:** Con số "14.324 đơn" ghi nhận ban đầu và mọi chỗ đã trích dẫn
cần sửa lại thành 14.330 khi viết README. Đã kiểm chứng bằng đối chiếu
`SUM(paidPrice)` giữa `fact_order_item` và `dim_order` sau khi gộp theo khoá
kép — khớp tuyệt đối (1.763.127.965), xác nhận không mất/trùng dòng nào.

---

## 13. Lỗi chữ hoa/thường trong shippingProvider

**Vấn đề:** `Vinacapital` và `vinacapital` là cùng một hãng vận chuyển nhưng
khác nhau ở chữ hoa/thường — tương tự lỗi dấu tiếng Việt trong SKU (mục 6).

**Xử lý:** Chuẩn hoá về `Vinacapital` khi tạo `fact_order_item`
(`sql/01_schema.sql`), trước khi dùng làm khoá cho `dim_shipping_provider`.

**Ảnh hưởng:** Nếu không gộp, `dim_shipping_provider` sẽ có 6 dòng thay vì 5
hãng thật, làm phân tích Bước 6 (thời gian giao theo `shippingProvider`) bị
chia nhỏ sai cho Vinacapital.

---

## 14. Cụm đơn vận hành nội bộ (≥20 sản phẩm/đơn) — không phải nhu cầu khách hàng thật

**Vấn đề:** 414 đơn có ≥20 sản phẩm/đơn (đỉnh ở đúng 30), trải dài 03/2021 –
03/2022, gần như toàn bộ `payMethod = COD`, `shop = Chetanic`. 355/414 đơn này
không hoàn tất, chiếm **64,5% tổng doanh thu thất thoát của toàn bộ dữ liệu**
(513.965.636đ / 796.499.415đ).

**Bằng chứng:** Phân bố `n_items` có khoảng trống tự nhiên giữa 16 và 20 sản
phẩm/đơn (không đơn nào có 17 hoặc 19 sản phẩm, chỉ 1 đơn có 18) — tách sạch
cụm này khỏi các đơn lớn nhưng hợp lệ khác (5–16 sản phẩm/đơn).

**Xử lý:** Đây là các đơn nội bộ liên quan tới cách vận hành chương trình flash
sale của shop, không phải nhu cầu mua hàng thật — loại hoàn toàn khỏi mọi phân
tích hành vi khách hàng. Thêm cột `is_bulk_operational` (`n_items >= 20`) vào
`dim_order`, và 2 view lọc sẵn dùng cho mọi truy vấn phân tích từ đây về sau:
`dim_order_customer`, `fact_order_item_customer` (xem `sql/01_schema.sql`).
**Không dùng `dim_order`/`fact_order_item` gốc cho câu hỏi về khách hàng nữa.**

**Ảnh hưởng — con số headline của cả project thay đổi đáng kể:**

| | Trước khi loại | Sau khi loại |
|---|---|---|
| Tổng số đơn | 14.330 | 13.916 |
| Tỷ lệ đơn không hoàn tất | 30,1% | **28,5%** |
| Doanh thu thất thoát (toàn kỳ) | 796.499.415đ | **282.533.779đ** |
| Đỉnh bất thường tháng 07/2021 | 181.557.024đ | 15.545.390đ (đã về mức bình thường) |

Con số "47,1% dòng không hoàn tất" ghi nhận ban đầu vẫn đúng về mặt đếm
dòng thô, nhưng khi diễn giải thành "doanh thu thất thoát vì khách hàng huỷ",
phải dùng bộ số ĐÃ LỌC ở trên — nếu không, phần lớn con số headline của cả
project thực chất phản ánh vận hành nội bộ, không phải hành vi khách hàng.
**Bắt buộc áp dụng cách lọc này cho cả Phân tích 2** (Flash sale có lãi
không) — nếu không, tỷ lệ huỷ của nhóm `campaign_flag = FS` sẽ bị thổi phồng
giả tạo bởi chính cụm đơn này, dẫn tới kết luận sai.

**Lưu ý khi đối chiếu với dashboard Power BI:** bảng trên dùng doanh thu GỘP
(`unitPrice`, chưa trừ `sellerDiscountTotal`) để khớp với `sql/02_phan_tich_1...`.
Dashboard Power BI (`docs/PowerBI-huong-dan-tung-buoc.md`) dùng
`doanh_thu_thuan = unitPrice - sellerDiscountTotal` (đã trừ discount, đúng quy
ước mục 15) nên số tuyệt đối sẽ khác — 756.472.283đ / 271.400.186đ thay vì
796.499.415đ / 282.533.779đ. Tỷ lệ % (30,1% / 28,5%) thì giống nhau ở cả 2 nơi
vì tỷ lệ tính trên số ĐƠN, không phụ thuộc cách tính doanh thu.
