# Đáp án Load

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `CI/CD A8.2` trỏ tới bộ tương ứng.

Stage này **mới thiết kế, chưa chạy**. Mọi câu ở thì hiện tại bên dưới nói về thiết kế, và câu đầu tiên của A1.1
nói rõ điều đó một lần. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **baseline** cho lần chạy ở chế độ Gemini để đọc T; **ramp** cho lần chạy
capacity ở chế độ fake; **điểm gãy** cho chỗ p95 bắt đầu tách khỏi p95 lúc tải thấp; **phép kiểm** cho một check.

**Số liệu đã có** — đo local ở phase app ([`../evidence/local.md`](../evidence/local.md)), được phép nói:

| Số | Giá trị | Dùng ở |
|---|---|---|
| Hai request `/recommend` ở chế độ Gemini, local | 3.0 s và 2.7 s | A3.8 |

**Còn phải điền:**

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| p95 phía server, T sau khi làm tròn lên, p95 của k6, số mẫu, số request lỗi | Lần chạy baseline | A1.3, A3.3, A3.8 |
| Tốc độ gửi của baseline | Lần chạy baseline | A3.6 |
| Tốc độ gửi cao nhất trước điểm gãy, in-flight mỗi pod tại đó, CPU của workstation | Lần chạy ramp | A1.3, A4.5 |
| Hệ số so với p95 lúc tải thấp dùng để xác định điểm gãy | Viết ra *trước* lần chạy ramp | A4.1 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi mới thiết kế, chưa chạy. Nó đo hai con số mà các stage sau không tự bịa ra
được. Một là T, ngưỡng latency của SLO, đọc từ histogram phía server trong một lần chạy thật với Gemini, ít nhất 200
request. Hai là bản deploy nhỏ nhất — hai pod, chưa có autoscaler — gánh được bao nhiêu, đo bằng fake provider với tốc
độ gửi tăng dần. Phần lớn công sức là ở chỗ: mỗi con số phải đo đúng thứ mà sau này nó sẽ phán xét."

*Nếu được hỏi thêm:* T ở A3.1, capacity ở A4.1, vì sao hai chế độ ở A5.1.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "thiết kế, chưa chạy", rồi trình bày tự nhiên.

**A1.2** **Ý chính:** "SLO cần một ngưỡng latency, autoscaler cần biết một pod gánh được bao nhiêu trước khi đuối.
Chọn theo cảm giác thì mọi phép kiểm về sau thừa hưởng một phỏng đoán được gọi là ngưỡng. Và một phỏng đoán sai theo
hướng rộng thì không bao giờ báo động, nên không ai phát hiện."

**A1.3** **Ý chính:** "#6 là baseline: p95 phía server thành T, p95 của k6 ghi bên cạnh, cùng số mẫu. #7 là capacity:
tốc độ gửi cao nhất mà hai pod chịu được trước điểm gãy, không có iteration nào bị bỏ. Kèm theo là số pod, số node và
tỉ lệ lỗi theo thời gian."

*Nếu được hỏi thêm:* kết quả `[điền: p95 phía server, T, p95 của k6, số mẫu, số lỗi]` và `[điền: tốc độ gửi cao nhất,
in-flight mỗi pod, CPU workstation]`.

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

*Nếu được hỏi thêm:* p95 của k6 được ghi cạnh T như con số một client gọi thẳng api phải chờ:
`[điền: p95 phía server và p95 của k6]`.

**Mẹo:** tự nói ra là chênh lệch nhỏ. Người nghe sẽ tin quy tắc hơn khi bạn không phóng đại lợi ích của nó.

**A3.4** **Ý chính:** "Vì SLO hỏi counter *tại* T, mà counter chỉ tồn tại ở ranh giới bucket. Hỏi một giá trị nằm
giữa hai ranh giới thì selector không khớp series nào, và SLO trả về rỗng — không phải một ước lượng, cũng không
phải số không. Một SLO như vậy không bao giờ được tính và không bao giờ báo động, trong khi file rule trông hoàn toàn
hợp lý."

*Nếu được hỏi thêm:* selector khớp chuỗi chính xác, nên cách viết con số cũng phải khớp — ví dụ `3.0` so với `3`
**[kiểm chứng: định dạng `le` mà client Python xuất ra]**.

**A3.5** **Ý chính:** "Chúng quá thô. Hiện là 0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32 giây, nên T chỉ nhảy được từ 2 lên 4
lên 8. Tệ hơn là cổng latency của canary: với latency của fake provider, gate viết là 1.2 lần thực tế chỉ bắn ở khoảng
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

*Nếu được hỏi thêm:* baseline gửi ở tốc độ mà tier miễn phí cho phép: `[điền: tốc độ gửi của baseline]`.

**A3.7** **Ý chính:** "Tuỳ lỗi đến từ đâu. Lỗi trả về nhanh — 503 từ phía model, hay 500 khi phần embedding lỗi — nằm
chung phân phối với request thành công, vì histogram không chia theo mã trạng thái, và kéo p95 xuống. Nhưng trong
đường gọi có retry với backoff, nên rate limit cũng có thể làm request chậm đi và đẩy T lên **[kiểm chứng: client
Gemini có retry khi bị giới hạn tốc độ không]**. Vì vậy baseline ghi lại số lỗi, để nhận ra T bị méo theo chiều nào."

*Nếu được hỏi thêm:* SLI cũng đếm lỗi như vậy, nên T và SLI vẫn nhất quán với nhau.

**A3.8** **Ý chính:** "Không, và đó là chủ ý. Local, hai request đơn lẻ tới Gemini mất 3.0 và 2.7 giây, nhưng hai mẫu
không nói gì về p95 của hai trăm request bị giới hạn tốc độ — có thể cao hơn nhiều. T rơi vào bucket nào là câu trả
lời của phép đo, không phải thứ để xác nhận."

*Nếu được hỏi thêm:* kết quả `[điền: T sau khi làm tròn lên]`.

### A4. Capacity

**A4.1** **Ý chính:** "Cấu hình nhỏ nhất: hai pod, chưa có autoscaler. Chạy với fake provider để đẩy mạnh mà không tốn
tiền, trong 10 phút, với tốc độ gửi tăng dần. Tiêu chí xác định điểm gãy được viết ra trước khi chạy, không chọn sau
khi đã nhìn đồ thị."

*Nếu được hỏi thêm:* tiêu chí đó là `[điền: hệ số so với p95 lúc tải thấp]`.

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

**A4.5** **Ý chính:** "Tại điểm gãy, lần ramp biết mỗi pod đang giữ bao nhiêu request in-flight. Ngưỡng của autoscaler
được đặt thấp hơn con số đó một chút, để scale bắt đầu *trước* điểm gãy chứ không phải *tại* nó. CPU và memory mỗi pod
đo trong lần ramp cũng là căn cứ cho resource request."

*Nếu được hỏi thêm:* kết quả `[điền: in-flight mỗi pod tại điểm gãy]`. Gauge in-flight tăng trước khi handler
chạy, nên nó đếm cả request đang xếp hàng chờ thread — middleware tăng gauge trước khi handler chờ thread; tôi
ghi nó cạnh số thread. Vì sao scale theo in-flight chứ không theo CPU nằm ở stage Scaling.

**A4.6** **Ý chính:** "Hiện `/healthz`, `/readyz` và `/metrics` là handler đồng bộ, nên chúng chạy chung một thread pool
có giới hạn với các lời gọi model của `/recommend` — bốn mươi thread, mặc định của thư viện bên dưới **[kiểm chứng]**.
Lúc bão hoà, một lần scrape phải xếp hàng sau các thread đang bận và timeout, nên series in-flight biến mất khỏi kết quả
query đúng lúc autoscaler cần nó. Probe cũng xếp hàng như vậy: readiness có thể rút một pod đang bận khỏi load balancer,
còn liveness có thể khiến kubelet khởi động lại nó — tệ hơn nữa. Cả ba không làm việc chặn nào, nên chúng chuyển thành
`async def` và chạy trên event loop, trước lần ramp."

*Nếu được hỏi thêm:* chính thread pool đó có lẽ là giới hạn capacity ở chế độ fake — một trần về đồng thời chứ không
phải CPU. Đó là lý do một điểm gãy ở chế độ fake vẫn nói được điều gì đó về việc scale ở chế độ thật.

### A5. Hai chế độ

**A5.1** **Ý chính:** "Mỗi con số có một nơi dùng, và được đo trong chế độ mà nơi dùng đó sẽ gặp. T dành cho SLO, mà
SLO chấm traffic thật, nên baseline gọi Gemini — và cả API embedding của Hugging Face, vì mỗi request thật đều đi qua
nó. Capacity dành cho autoscaler, và cần đẩy mạnh, lặp lại chính xác, không tốn tiền, nên dùng fake provider."

**A5.2** **Ý chính:** "Vì latency của fake provider là một thông số cấu hình — p95 dưới hai giây, chỉ bằng một phần của
bất kỳ T hợp lý nào. So nó với T thì lần chạy vẫn pass trong suốt giai đoạn đầu của bão hoà, và chỉ trượt khi thiệt hại
đã xảy ra từ lâu. Nên mỗi con số được ghi kèm chế độ ngay trên cùng một dòng."

**A5.3** **Ý chính:** "Nó nói nền tảng — routing, lập lịch, phần việc của chính app — gánh được bao nhiêu. Nó không nói
gì về việc provider chấp nhận bao nhiêu lời gọi thật. Ở chế độ fake, cả embedding cũng là giả, nên đường gọi thật không
nằm trong con số."

### A6. Pass mà vẫn hỏng

**A6.1** **Ý chính:** "Ba cách. Ngưỡng đo ở chế độ fake mà thực thi với traffic Gemini, hoặc ngược lại. T đọc từ k6 mà
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

**A7.1** **Ý chính:** "Khi chạy xong, stage này sẽ chứng minh: api được scrape; T đọc ở phía server từ đủ request thật,
có số lỗi bên cạnh; capacity của bản deploy nhỏ nhất và in-flight mỗi pod tại điểm gãy, với máy chạy k6 đã được loại
trừ. Nó giả định rằng latency của provider trong một buổi chiều đại diện cho những ngày khác. Và rằng workstation, ở một
VPC khác, đi tới ALB public gần giống một client gọi thẳng — gần giống, nhưng không y hệt."

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
