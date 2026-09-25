# Đáp án Load

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `CI/CD A8.2` trỏ tới bộ tương ứng.

Stage này **đã chạy xong**: criterion #6 (T) **pass**, criterion #7 (capacity) **partly measured** — trần thì vững,
còn con số capacity có điều kiện hợp lệ trượt ở cả hai lần ramp ([evidence](../evidence/load.md)). Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **baseline** cho lần chạy ở chế độ thật — OpenAI `gpt-4o-mini` — để đọc T; **ramp** cho lần chạy
capacity ở chế độ fake; **điểm gãy** cho chỗ p95 bắt đầu tách khỏi p95 lúc tải thấp; **phép kiểm** cho một check.

**Số liệu đã đo** ([`../evidence/load.md`](../evidence/load.md), 2026-09-23):

| Đọc được | Giá trị | Chế độ | Dùng ở |
|---|---|---|---|
| **T** | **8 s** | real, `gpt-4o-mini` | A2.1, A3.3 |
| p95 phía server, nội suy | 7.07 s | real | A3.3, A3.8 |
| p95 của k6 | 6.28 s | real | A3.8 |
| Số request đếm phía server, số 5xx | 230 (k6 gửi 231), **0** | real | A1.3, A3.3 |
| Tốc độ gửi của baseline | 10 request mỗi phút | real | A3.6 |
| Hệ số xác định điểm gãy, viết trước khi chạy | **1.5 ×** p95 tải thấp | — | A4.1 |
| p95 tải thấp → ngưỡng | 1.432 s → 2.148 s (lần 1); 1.453 s → 2.179 s (lần 2) | fake | A4.1 |
| **Trần phục vụ, 2 pod** | **93.9 req/s**, cả hai lần chạy | fake | A1.3, A4.5 |
| Giới hạn thread pool, tính trước khi chạy | 40 / 0.85 s = 47 mỗi pod, **94.1** cho hai | — | A4.5 |
| CPU / RAM mỗi pod tại trần | 0.23 core / 143 MiB | fake | A4.5 |
| p95 ở đỉnh ramp 120 req/s | 15.1 s (lần 1), **15.6 s** (lần 2) | fake | A4.5 |
| CPU cao nhất của workstation | 46% và 54% — không bị bão hoà | — | A4.5 |
| Hai request `/recommend` chế độ Gemini, local | 3.0 s và 2.7 s | real, local | A3.8 |

**Hai con số bị loại, và phải nói là bị loại:**

| Đọc được | Vấn đề | Dùng ở |
|---|---|---|
| Capacity theo quy tắc đặt trước: **88.2** và **89.1 req/s** | Điều kiện hợp lệ — không có iteration bị bỏ trước điểm capacity — **trượt cả hai lần** (sớm 4 phút, rồi sớm 5 giây). Quote **trần 93.9**, không quote capacity | A4.1, A7.1 |
| in-flight mỗi pod tại điểm gãy: **170.5** và **117.5** | Lệch 45%, **không tái lập**. Điểm gãy dò trên cửa sổ rate 2 phút, in-flight là gauge tức thời, lưới mẫu 30 s trên đoạn dốc gần thẳng đứng. Lần chạy thứ ba sẽ cho con số thứ ba cũng tuỳ ý như vậy, nên không chạy | A4.5, A7.1 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi đã chạy xong: T pass, capacity đo được một nửa. Nó đo hai con số mà các stage
sau không tự bịa ra được. Một là T, ngưỡng latency của SLO, đọc từ histogram phía server trong một lần chạy thật trên
**OpenAI `gpt-4o-mini`** — 230 request, 0 lỗi, T = 8 giây. Hai là bản deploy nhỏ nhất — hai pod, chưa có autoscaler —
gánh được bao nhiêu, đo bằng fake provider với tốc độ gửi tăng dần: trần 93.9 req/s, hai lần chạy khớp nhau. Phần lớn
công sức là ở chỗ: mỗi con số phải đo đúng thứ mà sau này nó sẽ phán xét.

*Nếu được hỏi thêm:* T ở A3.1, capacity ở A4.1, vì sao hai chế độ ở A5.1.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "tôi đã chạy stage này; T pass, capacity thì đo
được một nửa", rồi trình bày tự nhiên. Nói "một nửa" trước khi bị hỏi thì nó thành sự cẩn thận, nói sau thì thành
lời bào chữa.

**A1.2** **Ý chính:** "SLO cần một ngưỡng latency, autoscaler cần biết một pod gánh được bao nhiêu trước khi đuối.
Chọn theo cảm giác thì mọi phép kiểm về sau thừa hưởng một phỏng đoán được gọi là ngưỡng. Và một phỏng đoán sai theo
hướng rộng thì không bao giờ báo động, nên không ai phát hiện."

**A1.3** **Ý chính:** "#6 là baseline: p95 phía server thành T, p95 của k6 ghi bên cạnh, cùng số mẫu. #7 là capacity:
tốc độ gửi cao nhất mà hai pod chịu được trước điểm gãy, không có iteration nào bị bỏ. Kèm theo là số pod, số node và
tỉ lệ lỗi theo thời gian."

*Nếu được hỏi thêm:* baseline cho p95 phía server nội suy **7.07 s**, nên **T = 8 s**; p95 của k6 **6.28 s**; 230
request đếm phía server, **0** lỗi. Ramp cho **trần 93.9 req/s** ở cả hai lần, CPU workstation cao nhất 46% và 54% nên
máy phát tải không phải là giới hạn; còn in-flight mỗi pod tại điểm gãy ra 170.5 rồi 117.5 — không tái lập, nên không
dùng.

### A2. Dữ liệu có tồn tại không

**A2.1** **Ý chính:** "Vì trước khi đo gì, phải chứng minh là có dữ liệu để đo. Một cấu hình scrape mà monitoring
stack không chọn vẫn được cụm chấp nhận, và bị bỏ qua mà không có lời nào. Không gì báo lỗi; mọi query chỉ trả về
rỗng. Nên phép kiểm đầu tiên là tìm target của api theo tên và đòi nó phải up."

**A2.2** **Ý chính:** "Vì dashboard và alert đều khiến nó trông vô hại. Một alert trên dữ liệu không tồn tại không
bao giờ bắn, trừ khi viết riêng một alert cho sự vắng mặt. Một panel hiện 'No data', rất dễ lướt qua — và cách sửa
thường gặp là coi vắng mặt là số không cho đồ thị gọn, biến 'không đo gì cả' thành một đường xanh phẳng. Hệ thống
chưa được đo mà vẫn báo là ổn: ví dụ rõ nhất của một phép kiểm không thể thất bại."

**Mẹo:** "rỗng không phải là không" là ý sẽ quay lại ở SLO, delivery và scaling. Nói nó rõ ở đây.

**A2.3** **Ý chính:** "Trên counter tổng số request, trong đúng cửa sổ sắp dùng. Không kiểm trên counter lỗi, vì nó
không có mẫu nào cho tới lỗi đầu tiên — một service khoẻ sẽ trượt phép kiểm đó."

**A2.4** **Ý chính:** "Qua một PodMonitor trong chart của app. Từ stage 5 sẽ có ba Service cùng chọn pod api — Service
gốc, stable và canary. Cả hai loại monitor đều chép được label pod mà canary cần; cái quyết định là việc scrape trùng.
Một ServiceMonitor chỉ chọn Service gốc cũng tránh được, nhưng chỉ cần một selector rộng hơn là số đếm nhân đôi mà
không có lỗi nào. PodMonitor loại hẳn khả năng đó."

*Nếu được hỏi thêm:* mặc định monitoring stack chỉ chọn object mang label release của chính nó, nên selector được
mở ra để nhận monitor bất kể label. Alert rule có một selector riêng, giống hệt, và cũng phải mở. Không mở thì rule
được chấp nhận mà không bao giờ bắn.

### A3. T

**A3.1** **Ý chính:** "T là ngưỡng latency của SLO: phần request hoàn thành trong T trên tổng số request. Nó được đọc
từ chính histogram phía server mà SLI sẽ đếm, chỉ route `/recommend`, trong đúng cửa sổ thời gian của baseline. Rồi
nó được làm tròn lên ranh giới bucket gần nhất phía trên — hoặc giữ nguyên nếu p95 rơi đúng ranh giới."

*Nếu được hỏi thêm:* phải lọc route vì probe health và readiness cũng vào cùng histogram, nhanh hơn nhiều, và baseline
chạy chậm nên probe có thể nhiều hơn request thật. Giá trị nội suy của `histogram_quantile` chỉ là ước lượng, nhưng
p95 rơi vào bucket nào thì đọc thẳng từ các counter — nên việc làm tròn lên ranh giới của bucket đó là chính xác.

**A3.2** **Ý chính:** "Vì SLO được tính trên histogram của server. Một ngưỡng đo ở một chỗ mà thực thi ở chỗ khác thì
lệch đúng bằng khoảng chênh giữa hai chỗ, trên mọi request, mãi mãi. k6 còn tính thêm một vòng mạng, thời gian của
load balancer, và phần việc của server trước khi middleware bắt đầu đếm giờ."

*Nếu được hỏi thêm:* thời gian request của k6 chỉ gồm gửi, chờ và nhận. DNS, kết nối và TLS handshake được đo thành
metric riêng, và với keep-alive chúng chỉ xảy ra một lần mỗi kết nối.

**A3.3** **Ý chính:** "Tôi dự kiến nhỏ: vài mili giây, so với bucket rộng từ một phần tư tới nửa giây quanh vùng T,
nên sau khi làm tròn nó hiếm khi đổi T. Tôi vẫn giữ quy tắc vì nó đúng, và vì bản ghi nên nói nó quan trọng tới đâu
thay vì giả định."

*Nếu được hỏi thêm:* p95 của k6 được ghi cạnh T như con số một client gọi thẳng api phải chờ: **7.07 s** phía
server và **6.28 s** ở k6. Chiều lệch không phải vì server chậm hơn — 6.28 s là order statistic của k6, còn 7.07 s là
nội suy qua một bucket rộng 2 giây; chỉ mép bucket được dùng.

**Mẹo:** tự nói ra là chênh lệch nhỏ. Người nghe sẽ tin quy tắc hơn khi bạn không phóng đại lợi ích của nó.

**A3.4** **Ý chính:** "Vì SLO hỏi counter *tại* T, mà counter chỉ tồn tại ở ranh giới bucket. Hỏi một giá trị nằm
giữa hai ranh giới thì selector không khớp series nào, và SLO trả về rỗng — không phải một ước lượng, cũng không
phải số không. Một SLO như vậy không bao giờ được tính và không bao giờ báo động, trong khi file rule trông hoàn toàn
hợp lý."

*Nếu được hỏi thêm:* selector khớp chuỗi chính xác, nên cách viết con số cũng phải khớp — ví dụ `3.0` so với `3`.
Client Python xuất `le="8.0"`, và rule SLO viết đúng như vậy (`deploy/slo/anime-api.sloth.yaml`).

**A3.5** **Ý chính:** "Chúng từng quá thô. Trước stage này là 0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32 giây, nên T chỉ nhảy được từ 2
lên 4 lên 8 — nay là 16 ranh giới (`src/anime/metrics.py`). Tệ hơn là cổng latency của canary: với latency của fake provider, gate viết là 1.2 lần thực tế chỉ bắn ở khoảng
1.43 lần. Lý do là ước lượng không vượt được ranh giới 2 giây cho tới khi hơn 5% request vượt nó. Bucket mới dày hơn
quanh 1 tới 3 giây — thêm 0.75, 1.25, 1.5, 1.75, 2.5, 3 và 6 — để gate bắn ở khoảng 1.22 lần và T có thể là 2.5 hay 3.
Đó là một thay đổi trong code metric của app, làm trước cả hai lần chạy của stage này, vì T được đọc từ chính các
bucket đó."

*Nếu được hỏi thêm:* 1.43 và 1.22 là tính toán trên phân phối latency được cấu hình của fake provider, không phải số
đo. Chúng giả định canary chậm đều theo một hệ số và bỏ qua overhead; ngay p95 của stable cũng bị nội suy thành khoảng
1.82 giây trong khi thật là 1.42. Cổng canary thuộc stage Delivery.

**A3.6** **Ý chính:** "Vì p95 do một phần hai mươi chậm nhất quyết định. Sáu mươi request thì chỉ có ba mẫu ở đuôi;
hai trăm thì có mười. Khi các giá trị gần đó nằm vắt qua một ranh giới bucket, chỉ một request chậm cũng quyết định T
rơi vào bucket nào. Baseline gọi model thật và bị giới hạn tốc độ, nên nó chạy chậm và rất dễ muốn dừng sớm. Thời
lượng đi theo số lượng, không phải ngược lại."

*Nếu được hỏi thêm:* baseline gửi ở tốc độ mà tier miễn phí cho phép: **10 request mỗi phút**, trong 1386 giây.

**A3.7** **Ý chính:** "Tuỳ lỗi đến từ đâu. Lỗi trả về nhanh — 503 từ phía model hay từ phần embedding — nằm
chung phân phối với request thành công, vì histogram không chia theo mã trạng thái, và kéo p95 xuống. Còn retry thì ở đường gọi OpenAI **không có**: một lời gọi, thất bại là một
`UpstreamError` rồi 503 ngay, nên T không bị retry che. (Đường Gemini thì có `max_retries=1` và không test nào phủ
nó **[kiểm chứng]**.) Vì vậy baseline ghi lại số lỗi, để nhận ra T bị méo theo chiều nào."

*Nếu được hỏi thêm:* SLI cũng đếm lỗi như vậy, nên T và SLI vẫn nhất quán với nhau.

**A3.8** **Ý chính:** "Không, và đó là chủ ý. Local, hai request đơn lẻ tới Gemini mất 3.0 và 2.7 giây, nhưng hai mẫu
không nói gì về p95 của hai trăm request bị giới hạn tốc độ — có thể cao hơn nhiều. T rơi vào bucket nào là câu trả
lời của phép đo, không phải thứ để xác nhận."

*Nếu được hỏi thêm:* p95 thật rơi trong bucket 6–8 s, `histogram_quantile` nội suy ra 7.07 s, nên T là mép trên
của bucket đó: **8 s**.

### A4. Capacity

**A4.1** **Ý chính:** "Cấu hình nhỏ nhất: hai pod, chưa có autoscaler. Chạy với fake provider để đẩy mạnh mà không tốn
tiền, trong 10 phút, với tốc độ gửi tăng dần. Tiêu chí xác định điểm gãy được viết ra trước khi chạy, không chọn sau
khi đã nhìn đồ thị."

*Nếu được hỏi thêm:* tiêu chí đó là **1.5 lần p95 lúc tải thấp**, với p95 tải thấp là trung bình bốn điểm p95 đầu
ở lưới 30 giây — đo được 1.432 s và 1.453 s, nên ngưỡng là 2.148 s và 2.179 s. Cùng với nó là hai điều kiện hợp lệ,
và chính chúng đã trượt: xem A7.1.

**A4.2** **Ý chính:** "Mô hình đóng giả lập một số người dùng cố định, mỗi người chờ câu trả lời rồi mới hỏi tiếp.
Service chậm thì họ hỏi thưa đi, và những request lẽ ra đã được gửi trong lúc chậm không bao giờ được gửi, cũng không
bao giờ được đếm giờ — đó là coordinated omission. Mô hình mở gửi theo một tốc độ đặt trước, bất kể câu trả lời. Khi
service tụt lại, hàng đợi hình thành và latency tăng thật. Khi k6 không đủ worker để bắt đầu một request, nó đếm
request đó là bị bỏ. Điểm gãy nhờ đó hiện ra."

*Nếu được hỏi thêm:* mô hình đóng vẫn thấy được trần throughput; cái nó giấu là hàng đợi. Và mô hình mở cũng quay lại
coordinated omission khi hết worker, nên số worker tối đa được tính theo định luật Little — tốc độ nhân latency — cộng
khoảng dư.

**A4.3** **Ý chính:** "Nhìn CPU của workstation. Chỉ số iteration bị bỏ không phân biệt được, vì một service đang chậm
cũng làm cạn pool worker của k6. Nếu p95 tách ra trong khi CPU workstation còn dư thì đó là giới hạn của hai pod — con
số tôi cần. Nếu CPU workstation đã kịch thì đó là giới hạn của bài test, và con số không được dùng. Và kiểm số worker
đang dùng so với mức tối đa: chạm trần thì iteration bị bỏ vì cấu hình script, không phải vì service hay CPU."

*Nếu được hỏi thêm:* nếu nhầm, autoscaler được chỉnh theo một con số thấp hơn thực tế, và scale sớm hơn, thường hơn
service cần — một chi phí trả vào mỗi giờ cao điểm, cho một con số mô tả máy test.

**A4.4** **Ý chính:** "Không. Số replica cố định, nên không có pod mới nào được yêu cầu, và node group không bao giờ bị
chạm tới trần. Trần đó thuộc về lần chạy autoscaling ở stage sau."

**A4.5** **Ý chính:** "Thiết kế định đọc số in-flight mỗi pod tại điểm gãy rồi đặt ngưỡng autoscaler thấp hơn một chút.
Nhưng con số đó không lặp lại được giữa hai lần chạy, nên ngưỡng — 30 — lấy từ giới hạn nó thay mặt: 40 thread mỗi pod,
mà trần 93.9 req/s xác nhận. CPU và memory mỗi pod đo trong lần ramp là căn cứ cho resource request."

*Nếu được hỏi thêm:* nó ra **170.5** ở lần 1 và **117.5** ở lần 2 — lệch 45%, nên tôi không dùng con số này.
Cụm cư xử giống nhau cả hai lần, trần 93.9 req/s chứng minh điều đó, nên chỗ bất định nằm ở *dụng cụ đo* chứ không ở
hệ thống. Ngưỡng cho KEDA vì thế lấy từ giới hạn kiến trúc mà nó đang thay mặt: 40 luồng mỗi pod, nên in-flight trên
40 nghĩa là có hàng đợi — một định nghĩa, và các phép đo đồng ý với nó (ở 83 req/s pod giữ 46.5 in-flight mà p95 vẫn
1.46 s, điểm tiếp theo thì tách hẳn). Gauge in-flight tăng trước khi handler
chạy, nên nó đếm cả request đang xếp hàng chờ thread — middleware tăng gauge trước khi handler chờ thread; tôi
ghi nó cạnh số thread. Vì sao scale theo in-flight chứ không theo CPU nằm ở stage Scaling.

**A4.6** **Ý chính:** "Trước stage này `/healthz`, `/readyz` và `/metrics` là handler đồng bộ, nên chúng chạy chung một thread pool
có giới hạn với các lời gọi model của `/recommend` — bốn mươi thread, mặc định của thư viện bên dưới, và trần 93.9 req/s
khớp đúng phép tính 40 thread (`evidence/load.md`).
Lúc bão hoà, một lần scrape phải xếp hàng sau các thread đang bận và timeout, nên series in-flight biến mất khỏi kết quả
query đúng lúc autoscaler cần nó. Probe cũng xếp hàng như vậy: readiness có thể rút một pod đang bận khỏi load balancer,
còn liveness có thể khiến kubelet khởi động lại nó — tệ hơn nữa. Cả ba không làm việc chặn nào, nên chúng đã chuyển thành
`async def` và chạy trên event loop, trước lần ramp."

*Nếu được hỏi thêm:* chính thread pool đó là giới hạn capacity ở chế độ fake (đã xác nhận: trần 93.9 req/s, 0.23 core mỗi pod) — một trần về đồng thời chứ không
phải CPU. Đó là lý do một điểm gãy ở chế độ fake vẫn nói được điều gì đó về việc scale ở chế độ thật.

### A5. Hai chế độ

**A5.1** **Ý chính:** "Mỗi con số có một nơi dùng, và được đo trong chế độ mà nơi dùng đó sẽ gặp. T dành cho SLO, mà
SLO chấm traffic thật, nên baseline gọi model thật — **OpenAI `gpt-4o-mini`** — và cả API embedding của Hugging
Face, vì mỗi request thật đều đi qua nó. T thuộc về đúng provider ấy: đo trên Gemini sẽ ra một số khác, và SLO phải đo
lại. Tôi chọn `gpt-4o-mini` vì Gemini mất khoảng 50 giây một lời gọi trong khi nó trả lời trong 1–3 giây. Capacity dành cho autoscaler, và cần đẩy mạnh, lặp lại chính xác, không tốn tiền, nên dùng fake provider."

**A5.2** **Ý chính:** "Vì latency của fake provider là một thông số cấu hình — p95 dưới hai giây, chỉ bằng một phần của
bất kỳ T hợp lý nào. So nó với T thì lần chạy vẫn pass trong suốt giai đoạn đầu của bão hoà, và chỉ trượt khi thiệt hại
đã xảy ra từ lâu. Nên mỗi con số được ghi kèm chế độ ngay trên cùng một dòng."

**A5.3** **Ý chính:** "Nó nói nền tảng — routing, lập lịch, phần việc của chính app — gánh được bao nhiêu. Nó không nói
gì về việc provider chấp nhận bao nhiêu lời gọi thật. Ở chế độ fake, cả embedding cũng là giả, nên đường gọi thật không
nằm trong con số."

### A6. Pass mà vẫn hỏng

**A6.1** **Ý chính:** "Ba cách. Ngưỡng đo ở chế độ fake mà thực thi với traffic real mode, hoặc ngược lại. T đọc từ k6 mà
thực thi trên histogram của server. Và một p95 từ vài chục request, mà một lời gọi chậm có thể đẩy sang bucket khác."

**A6.2** **Ý chính:** "Ba cách. Ramp theo mô hình đóng, thấy được trần nhưng giấu hàng đợi. Một điểm đi ngang thật ra là
của máy chạy k6, bị đọc thành giới hạn của service. Và so p95 của lần ramp với T, thứ chỉ trượt rất lâu sau khi bão hoà
đã bắt đầu."

**A6.3** **Ý chính:** "Một con số đúng, nhưng đúng về một thứ khác với thứ nó sẽ được dùng. Một percentile dựa trên
một nhúm mẫu. Một capacity thật ra là của máy test. Một latency đẹp nhờ những lần từ chối nhanh. Một query không có dữ
liệu bị đọc thành 'mọi thứ ổn'."

**Mẹo:** so với GitOps A7.4 và CI/CD A8.2 — mỗi stage có một dạng pass sai riêng. Nêu được dạng của từng stage là dấu
hiệu bạn hiểu cả hệ thống.

### A7. Giới hạn

**A7.1** **Ý chính:** "Stage này đã chứng minh: api được scrape; T đọc ở phía server từ 230 request thật với 0 lỗi
bên cạnh; và một cái trần 93.9 req/s cho bản deploy nhỏ nhất, đo hai lần khớp nhau và khớp với giới hạn thread pool
94.1 tính trước khi chạy. Máy chạy k6 đã được loại trừ: CPU cao nhất 46% và 54%.

Hai thứ nó **không** chứng minh, và tôi nói ra trước khi bị hỏi. Capacity theo quy tắc đặt trước — 88 tới 89 req/s —
có điều kiện hợp lệ trượt ở cả hai lần, nên tôi quote trần chứ không quote capacity. Và in-flight tại điểm gãy không
tái lập được, 170.5 so với 117.5; lần thứ ba sẽ lấy mẫu cùng đoạn dốc theo cùng cách, nên nó không được chạy.

Nó cũng giả định rằng latency của provider trong một buổi chiều đại diện cho những ngày khác. Và rằng workstation, ở
một VPC khác, đi tới ALB public gần giống một client gọi thẳng — gần giống, nhưng không y hệt."

**A7.2** **Ý chính:** "Metric mất cùng cụm mỗi lần teardown. Nên bằng chứng của mỗi lần chạy được lưu ngay lúc đó —
output của k6 và kết quả các query — chứ không bao giờ đọc lại từ Prometheus về sau."

**A7.3** **Ý chính:** "T được đo lại, không dùng lại. T là thuộc tính của một model trên một tier, không phải của
service."

### A8. Nhìn lại

**A8.1** **Ý chính:** "Ở phase Jenkins của Medical có năm phép kiểm pass trong khi thứ chúng canh đã hỏng — ví dụ một
phép kiểm readiness lọc condition Ready theo type chứ không theo status, nên một pod chưa sẵn sàng vẫn được tính. Bài học
là phép kiểm phải đọc đúng thứ nó phán xét, và phải có khả năng thất bại. Nên stage này mở đầu bằng việc chứng minh có
dữ liệu, trước khi tin bất kỳ con số nào đọc từ đó."

**A8.2** **Ý chính:** "Tôi sẽ lấy T từ traffic thật trong vài tuần chứ không từ một buổi chiều, và xem nó thay đổi thế
nào theo giờ trong ngày. Còn capacity thì chạy load generator phân tán, gần người dùng hơn, để máy test không còn là
nghi phạm."

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)

---

### A10. Câu đào sâu — vì sao trần là 40 luồng

**A10.1** **Ý chính:** "Handler `/recommend` *đã là* `async def`. Cái nằm trong thread pool là hàm recommender đồng
bộ: handler gọi `run_in_threadpool(recommender.recommend, …)`, và pool mặc định của Starlette có 40 luồng — nên kích
thước pool *chính là* trần đồng thời của một pod. Đó là con số 40 trong phép tính 40 / 0.85 s = 47 req/s mỗi pod."

*Nếu được hỏi thêm:* việc dồn phần chặn vào pool là có chủ ý, và lý do nằm ở ba endpoint còn lại. `/healthz`,
`/readyz` và `/metrics` đều `async def`, có comment giải thích ngay trong code: một handler `def` thường sẽ chạy
trong *cùng* cái pool bị giới hạn ấy, nên một api đang bão hoà sẽ ngừng trả lời chính probe của nó — và Kubernetes
giết những pod chỉ đang bận. Tách ra như vậy nghĩa là khi pod tắc, nó vẫn nói được rằng nó còn sống.

Muốn nâng trần thì phải làm cuộc gọi provider async thật, bằng một HTTP client async — lúc đó đồng thời bị chặn bởi
socket và memory chứ không phải bởi luồng, cỡ hàng trăm in-flight mỗi pod. **Tín hiệu autoscale không đổi**, vẫn là
in-flight; chỉ ngưỡng cao hơn nhiều. Tôi cố ý không sửa app trong đợt này: mục đích là đo một *platform* trên một app
cố định, và sửa app giữa đường thì cái trần đã đo hai lần mất giá trị. Đó là thứ đầu tiên tôi đổi nếu mục tiêu là
throughput trên mỗi đô la thay vì một phép đo tái lập được.

**Mẹo:** câu hỏi này là chỗ dễ bị bắt nhất của cả bullet capacity, vì người hỏi sẽ giả định handler là `def` đồng bộ.
Sửa lại giả định đó ngay câu đầu, rồi mới giải thích — nếu không, mọi thứ sau đó nghe như đang bào chữa cho một
default không ai sửa.
