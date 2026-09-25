# Đáp án SLO

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Load A3.4` trỏ tới bộ tương ứng.

Stage này **đã chạy**: criterion #10 — page của fast burn tới được Discord trong drill — **pass**, 2026-09-23
([evidence](../evidence/slo.md)). Nói ở thì quá khứ được, nhưng chỉ với những gì evidence ghi. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **cặp** cho một cửa sổ dài ghép với một cửa sổ ngắn (cặp 1h/5m); **page**
cho alert gọi người ngay; **ticket** cho alert để xử lý trong vài ngày tới; **drill** cho lần cố ý tiêm lỗi để kiểm
alert.

**Số liệu đã đo** ([`../evidence/slo.md`](../evidence/slo.md), 2026-09-23, fake mode, 20 req/s, lỗi tiêm **50%
toàn bộ traffic**):

| Đọc được | Giá trị | Dùng ở |
|---|---|---|
| **T** | **8 s**, real mode `gpt-4o-mini`, từ 230 request | A2.1 |
| Prometheus **đánh giá** rule, không chỉ giữ | **6** rule group, **34** rule, **0** lần đánh giá lỗi | A6.5, A8.1 |
| Giờ sạch trước khi tiêm lỗi | **71997** request, **0** lỗi, store đã 9.67 giờ tuổi | A1.1 |
| Lỗi đầu tiên được **scrape** | +45 s | A6.5 |
| Recording rule ghi tỉ lệ 5 phút | +15 s | A6.5 |
| Số học cửa sổ | **+8 m 00 s** | A6.5 |
| **Alert `firing` trong Prometheus** | **9 m 00 s** từ lúc tiêm lỗi | A6.5 |
| **`[PAGE] … FIRING` trong Discord** | **9 m 30 s** — biên dưới, khoảng đúng 9:30–9:36 | A1.1, A6.5 |
| severity | `page` (route `{severity="page"}` → `discord-page`) | A1.1 |
| Error ratio lúc bắn | **0.497** | A1.1 |
| Delivery failure của Discord trong 30 phút trước | **0** | A8.1 |
| `group_wait` của Alertmanager | 30 s | A6.5 |
| **Cặp bắn:** 5m / 1h so với hệ số 13.44 | **99.43 / 14.66 — vượt cả hai** | A1.1, A5.2 |
| **Cặp không bắn:** 6h so với hệ số 5.6 | **5.30 — thiếu** | A5.2 |
| Alert tự tắt sau khi sửa lỗi | **26 m 06 s** | A6.3 |
| Traffic lúc alert tắt | 40 req/s ở cả 12:00 và 12:02 — nên không phải tắt vì hết traffic | A6.3 |

**Vì sao 9 phút chứ không phải 4 như guide dự đoán.** Guide trông chờ cặp **6h/30m** bắn trước vì hệ số của nó thấp
hơn. Cặp đó *không thể* thắng trên một store đã giữ hàng giờ traffic sạch: mẫu số 6 giờ lớn đến mức một lỗi 50% cần
khoảng hai mươi phút mới đẩy nó qua 5.6 — đo được 5.30. Cặp bắn là **1h/5m**, và điều đó làm con số *mạnh hơn*: nó là
cặp đã được hiệu chuẩn, cái có cửa sổ một giờ chứa đúng một giờ sạch. Guide đã sửa, với 5.30 ghi lại làm lý do.

| Chỗ còn trống | Vì sao | Dùng ở |
|---|---|---|
| Chu kỳ đánh giá rule | Không đặt trong `deploy/` — là default của chart, chưa đọc lại | A6.5 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi đã chạy drill, criterion #10 pass. Có hai SLO trên route chính của api:
availability 99.5%,
và 95% request dưới T — T đo ở stage Load. Mọi alert là ngưỡng trên burn rate, mỗi alert xét hai cửa sổ cùng lúc. Cặp
nhanh gọi người, cặp chậm mở ticket. Rule do Sloth sinh ra với hệ số cho chu kỳ 28 ngày, và được commit vào Git. Và tôi
nói thẳng: một nền tảng sống vài giờ mỗi ngày không bao giờ chứng minh được SLO đạt. Thứ nó chứng minh được là alert bắn
đúng rule và tới được người."

*Nếu được hỏi thêm:* drill chia thời gian ra được: 45 giây scrape, 15 giây recording rule, 8 phút số học cửa sổ —
alert `firing` sau 9 phút 00, tin `[PAGE] … FIRING` trong Discord ở **9 phút 30** (biên dưới; Discord chỉ hiện phút
nên khoảng đúng là 9:30–9:36). severity `page`, SLO availability 99.5%, error ratio lúc bắn 0.497. Cặp bắn là 1h/5m
với burn 14.66 và 99.43 so với hệ số 13.44, còn chân 6h chỉ 5.30 so với 5.6. Giờ sạch trước đó: 71997 request, 0
lỗi.

**Mẹo:** câu "không bao giờ chứng minh được SLO đạt" nên nói trước khi bị hỏi. Nó cho thấy bạn hiểu giới hạn của chính
thiết kế.

**A1.2** **Ý chính:** "Một bản lỗi bị bắt trong lúc canary, nhưng chỉ vậy. Provider sập, một buổi chiều chậm, một regression
chỉ lộ dưới traffic thật — hệ thống không nhận ra cái nào cho tới khi có người nhìn đồ thị. Và T đã đo ở stage Load nhưng
chưa có gì thực thi nó."

**A1.3** **Ý chính:** "Vì nó sai theo cả hai hướng. Đặt chặt thì gọi người vì mọi cú giật. Đặt lỏng thì một lỗi rỉ rả,
chậm mà đều, kéo dài cả tuần mà không ai hay."

### A2. SLO và ngân sách lỗi

**A2.1** **Ý chính:** "SLI là tỉ lệ sự kiện tốt trên tổng — request thành công, request nhanh hơn một ngưỡng. SLO là giá trị
mà tỉ lệ đó phải giữ trong một chu kỳ. Error budget là phần SLO chừa lại: tỉ lệ request được phép hỏng. Anime có hai SLO trên
`/recommend`, đều trên 28 ngày: availability 99.5%, và 95% request dưới T."

*Nếu được hỏi thêm:* chỉ route `/recommend`, nên probe và `/metrics` không làm đẹp SLI. Chỉ 5xx tính là lỗi; 4xx là lỗi của
client. Histogram không tách theo mã trạng thái, nên một 503 trả về nhanh được tính là "nhanh" trong SLO latency — nó bị
bắt ở SLO availability. T là **8 giây**, đo ở real mode trên `gpt-4o-mini` từ 230 request.

**A2.2** **Ý chính:** "Burn rate là tốc độ tiêu ngân sách, so với việc tiêu vừa khít trong cả chu kỳ. Burn rate 1 thì ngân
sách dùng đúng hết chu kỳ; burn rate n thì hết trong 1/n chu kỳ. Alert trên burn rate vì cùng một tỉ lệ lỗi mang nghĩa rất
khác với các SLO khác nhau. Burn rate chuẩn hoá điều đó, nên một kiểu alert dùng được cho mọi SLO, và mọi ngưỡng đọc thành
'bao lâu nữa thì hết ngân sách'."

**A2.3** **Ý chính:** "SLO latency dựng từ T. Một SLO có ngưỡng đoán mò sinh ra một ngân sách đoán mò, và mọi alert trên đó
thừa hưởng phỏng đoán. Còn một chi tiết kỹ thuật: SLI đếm counter tại `le=T`, nên T phải là một ranh giới bucket, nếu không
query trả về rỗng và alert không bao giờ bắn."

*Nếu được hỏi thêm:* `le` là một chuỗi, nên cách viết con số cũng phải khớp — ở đây là `le="8.0"`
(`deploy/slo/anime-api.sloth.yaml`); bucket không tồn tại thì cả
biểu thức rỗng. Chi tiết ở Load A3.4.

**A2.4** **Ý chính:** "Nó là một định nghĩa, không phải thứ đo được. Không cửa sổ 28 ngày nào tồn tại ở đây. Chu kỳ đó quyết
định kích thước ngân sách, và từ đó quyết định các ngưỡng alert. Không có gì trong project này sẽ tuyên bố SLO đã đạt."

*Nếu được hỏi thêm:* vì sao 99.5% thì design không ghi lý do. Quan điểm của tôi: trên 28 ngày nó cho khoảng 3.4 giờ lỗi, và
service dựa vào tier miễn phí của OpenAI và Hugging Face thì không thể hứa chặt hơn thứ nó phụ thuộc vào.

### A3. Hai cửa sổ, hai tốc độ

**A3.1** **Ý chính:** "Cửa sổ dài hỏi: burn này có thật, không phải một cú giật? Cửa sổ ngắn, dài khoảng một phần mười hai,
hỏi: nó còn đang xảy ra không? Alert chỉ bắn khi cả hai vượt ngưỡng. Chỉ cửa sổ dài thì chậm bắt đầu, và sau một đợt burn lớn
thì chậm dừng. Chỉ cửa sổ ngắn thì bắn theo mọi cú giật. Ghép lại thì nhanh theo cả hai chiều."

**A3.2** **Ý chính:** "Page làm gián đoạn một người ngay bây giờ; ticket là việc cho vài ngày tới. Hai cặp nhanh — 1h/5m và
6h/30m — page, vì với tốc độ đó ngân sách hết trong vài ngày. Hai cặp chậm — 1d/2h và 3d/6h — mở ticket: một lỗi rỉ rả đáng
sửa, nhưng không đáng đánh thức ai. Page và ticket tới cùng một kênh Discord, phân biệt bằng `[PAGE]` và `[TICKET]` ở tiêu đề."

*Nếu được hỏi thêm:* "ticket" ở đây chỉ là một tin nhắn có tiêu đề `[TICKET]`, không phải một hệ thống ticket thật. Route gốc
giữ receiver rỗng của chart, nên alert nào không khớp hai route đó thì không đi đâu cả.

**A3.3** **Ý chính:** "Mỗi hệ số là phần ngân sách mà nếu bị tiêu trong cửa sổ dài thì alert bắn, nhân chu kỳ, chia cửa sổ.
2% ngân sách của 672 giờ, trên một giờ, là 13.44. 5% trên sáu giờ là 5.6. 10% trên một ngày là 2.8. 10% trên ba ngày là
khoảng 0.93. Các con số quen thuộc 14.4, 6, 3, 1 là cùng các phần đó trên 720 giờ — chu kỳ 30 ngày."

*Nếu được hỏi thêm:* Sloth tự tính bộ cho 28 ngày khi được chạy với chu kỳ 28 ngày. Mặc định của nó là 30 ngày, nên chu kỳ
phải nằm cả trong lệnh CI chạy lại, nếu không rule đã commit lặng lẽ mang hệ số 30 ngày. Ở đây Makefile truyền
`--default-slo-period=28d`, và rule sinh ra mang 13.44 và 5.6.

**Mẹo:** người phỏng vấn biết 14.4 từ sách của Google. Giải thích được vì sao ở đây là 13.44 là một điểm cộng rõ ràng.

### A4. Rule được sinh ra

**A4.1** **Ý chính:** "Rule burn rate viết tay rất dễ sai số học — nhiều cửa sổ, hai SLO, recording rule bên dưới
alert. Sloth sinh chúng từ một spec ngắn. Output được commit thành một PrometheusRule thường, có Application Argo
CD riêng, và CI chạy lại `sloth generate` rồi thất bại nếu file đã commit khác đi — nên spec và rule không thể
lệch nhau. Không dùng operator vì không cần thêm một controller và một kiểu object nữa chỉ để làm việc mà CI đã
làm."

*Nếu được hỏi thêm:* không đưa qua Helm vì annotation của rule có cú pháp ngoặc nhọn của template Prometheus, và Helm sẽ cố
render chúng.

**A4.2** **Ý chính:** "Nó phải được *nạp*. Monitoring stack bỏ qua rule không mang label release của nó, trừ khi
được cấu hình khác — đúng cái bẫy im lặng mà stage Load gặp với target scrape. Một file rule không ai nạp thì
không có lỗi và không có alert, mãi mãi. Một drill chạy trên nó kết thúc bằng sự im lặng trông y hệt alert bị
hỏng."

*Nếu được hỏi thêm:* ở đây stack được cấu hình nạp rule bất kể label, và trước drill tôi kiểm rule có trong trang Rules của
Prometheus — vì Argo CD báo PrometheusRule là Healthy dù nó có được nạp hay không.

### A5. Cửa sổ dài hơn dữ liệu

**A5.1** **Ý chính:** "Nó không trả về rỗng một khi đã có chút dữ liệu. Burn rate là tỉ lệ của hai rate. Mỗi rate
chia cho cả độ dài cửa sổ, nhưng trong một tỉ số thì phần đó triệt tiêu — còn lại là lỗi trên tổng của những
request thật sự nằm trong cửa sổ. Nên một rule mang tên một ngày thực chất cư xử như rule cho vài giờ, và có thể
bắn vì một đợt ngắn mà nó được dựng ra để bỏ qua. Trước khi có dữ liệu nào, mọi cửa sổ đều rỗng và không gì bắn
được. Không trạng thái nào tự lộ ra; chỉ nhận ra bằng cách kiểm mỗi cửa sổ thật sự đang chứa bao nhiêu dữ liệu."

**A5.2** **Ý chính:** "Chỉ cặp 1h/5m được hiệu chỉnh cho phần lớn một phiên. Sloth gộp hai cặp page vào cùng một
alert bằng phép `or` — đã xác nhận trên file sinh ra — nên tôi không chọn được cặp, cặp nào vượt ngưỡng trước thì bắn.
Tôi từng tính rằng với một giờ sạch, nhánh 6h/30m sẽ bắn trước ở khoảng bốn phút. Drill chạy trên một giờ sạch, nhưng
store đã chứa nhiều giờ traffic sạch trước đó, nên cửa sổ 6h chỉ lên 5.30 so với 5.6 và cặp 1h/5m page ở 9 phút 30 giây.
Cặp nào bắn là điều tôi đọc ra từ burn của từng cửa sổ, không phải điều tôi đoán từ tên alert."

*Nếu được hỏi thêm:* điều quyết định là store chứa bao nhiêu traffic sạch, không phải drill chạy bao lâu trước lỗi:
mẫu số của cửa sổ 6h lớn thì lỗi 50% cần khoảng hai mươi phút mới đẩy nó qua 5.6. Hai cặp ticket vượt ngưỡng trong vài phút đầu dù thế nào, với tiêu đề `[TICKET]`, và được
ghi là chưa hiệu chỉnh.

**Mẹo:** đây là chỗ mà chính việc rà lại thiết kế đã tìm ra lỗi. Kể được "ban đầu tôi nghĩ một giờ sạch là đủ, tính lại thì
không" là một câu chuyện tốt.

### A6. Drill

**A6.1** **Ý chính:** "Một bản ở chế độ fake với 50% lỗi, promote thẳng lên toàn bộ traffic, sau một giờ traffic
sạch. Rồi đo thời gian tới khi page tới Discord, chia theo từng phần, và ghi `alertname`, severity, SLO
và burn của từng cửa sổ."

*Nếu được hỏi thêm:* bản đó phải ghim cả `LLM_PROVIDER=fake`, vì tỉ lệ lỗi chỉ được fake provider đọc — Delivery
A8.2. Page và ticket mang **cùng** tên alert, `AnimeApiAvailabilityBudgetBurn`, chỉ khác label `severity`
(`deploy/slo/generated/anime-api.yaml`) — nên tên alert một mình không đủ.

**A6.2** **Ý chính:** "Vì alert đọc tỉ lệ lỗi của cả service. Ở mức canary 10%, 50% lỗi thành 5% tổng — burn rate 10. Như vậy dưới ngưỡng 13.44 của cặp 1h/5m, nên cặp đó không bao giờ bắn; cặp 6h/30m với ngưỡng 5.6 chỉ bắn sau
hơn một tiếng, theo tính toán — lâu hơn một drill. Sự im lặng trong khoảng đó sẽ bị đọc nhầm thành alert hỏng.
Nên drill dùng lệnh promote toàn phần, bỏ qua các mức còn lại và phân tích của chúng."

**A6.3** **Ý chính:** "Vì số học của chính drill. Với SLO 99.5%, 10% lỗi là burn rate 20, và cửa sổ một giờ cần
khoảng bốn mươi phút để trung bình vượt 13.44 — một drill không ai ngồi chờ nổi, và dễ chồng lên teardown. 50%
lỗi là burn rate 100, và cặp 1h/5m vượt ngưỡng sau khoảng tám phút. Đó là tính toán cho riêng cặp 1h/5m, chưa đo,
và chưa cộng thời gian scrape, đánh giá rule, gom nhóm và gửi. Tôi ghi phép tính ra, để con số không bị hiểu nhầm
thành một điều kiện production."

**A6.4** **Ý chính:** "Vì traffic trước lúc tiêm lỗi quyết định drill đo cái gì. Sau traffic sạch, cửa sổ dài
tăng dần, và drill đo rule mất bao lâu để *nhận ra* một đợt burn. Không có traffic sạch thì cửa sổ chỉ thấy lỗi
ngay từ đầu, tỉ lệ là 50% ngay lần scrape đầu, và drill đo pipeline mất bao lâu để *gửi* page. Cả hai đều hợp lệ
nhưng trả lời hai câu hỏi khác nhau — nên bản ghi nói rõ là loại nào. Còn *bao nhiêu* traffic sạch thì quyết định
cặp nào bắn, như ở A5.2."

**A6.5** **Ý chính:** "Lần scrape đầu mang request lỗi; recording rule biến counter thành tỉ lệ, theo chu kỳ
riêng của nó; lần đánh giá alert rule đầu tiên thấy cả hai cửa sổ vượt ngưỡng — rule của Sloth không có thời gian
chờ thêm (không có `for:`), nên nó bắn luôn; thời gian gom nhóm của Alertmanager; và thời gian Discord gửi. Chỉ
phần số học cửa sổ là về SLO; phần còn lại là cấu hình. Ghi từng phần mới biến 'từ lỗi tới tin nhắn mất X phút'
thành thứ có thể làm nhanh hơn."

*Nếu được hỏi thêm:* thời gian chờ của Alertmanager khác nhau tuỳ alert mở một nhóm mới hay nhập vào một nhóm đã
gửi rồi. Thời gian từ lệnh promote tới khi pod lỗi gánh toàn bộ traffic cũng nằm trong tổng. Trong các giá trị cấu hình: `group_wait` **30 giây** và `group_interval` **5 phút** đều nằm trong Git, chu kỳ
scrape **30 giây** nằm trong PodMonitor của api — cả ba là **đọc từ chart**, không phải drill đo ra. Chu kỳ đánh giá
rule thì chart không đặt, nên tôi không đọc số. Kết quả chia phần: **45 s** scrape +
**15 s** recording rule + **8 m 00 s** số học cửa sổ = alert bắn ở 9 m 00 s, tin vào Discord ở **9 m 30 s**.

### A7. Gửi tới người

**A7.1** **Ý chính:** "Vì project này alert trên thứ người dùng cảm nhận, rồi điều tra nguyên nhân từ đó. Pod
crash-loop hay node không sẵn sàng không được gửi đi đâu: nếu nó làm người dùng đau, burn của SLO sẽ nói; nếu
không, nó là một nguyên nhân để điều tra, không phải lý do để đánh thức ai."

**A7.2** **Ý chính:** "Mỗi alert được gửi đi đều mang link tới một mục runbook, viết *trước* drill bắn nó. Page
tới vào lúc tệ nhất mà không có ngữ cảnh thì mấy phút đầu mất vào việc hiểu nó đang hỏi gì. Và viết mục runbook
trước cũng là phép thử xem có ai hành động được trên alert đó không."

**A7.3** **Ý chính:** "Là một alert luôn bắn, gửi tới một dịch vụ bên ngoài, và dịch vụ đó kêu khi nó ngừng tới.
Monitoring stack có sẵn một alert heartbeat như vậy, nhưng ở đây nó không được gửi đi đâu, vì không có dịch vụ
bên ngoài nào nhận. Hệ quả: nếu webhook hỏng giữa hai drill, page cứ thế biến mất và không gì báo. Việc gửi được
*chứng minh* ở mỗi drill và *giả định* ở giữa."

### A8. Pass mà vẫn hỏng

**A8.1** **Ý chính:** "Bốn cách. Rule chưa bao giờ được nạp — drill kết thúc không page, không lỗi. Lỗi bị pha
loãng ở mức canary, burn dưới ngưỡng, và im lặng bị đọc thành alert hỏng. Rule đã bắn nhưng webhook từ chối —
không gì tới, và không có dead-man's switch để bắt. Và sai cặp: trên một Prometheus mới chạy vài giờ, page từ cặp
6h/30m không phải cặp 1h/5m đã hiệu chỉnh đang hoạt động. Nên bản ghi mang `alertname`, severity, SLO, và burn
của từng cửa sổ lúc bắn — vì tên alert không cho biết cặp nào."

**A8.2** **Ý chính:** "Một alert đúng về số học nhưng sai về đầu vào — rule không ai nạp, cửa sổ tính từ ít dữ
liệu hơn tên của nó, lỗi bị canary pha loãng, webhook từ chối. Cách tránh lần nào cũng như nhau: ghi lại cái gì
đã bắn và vì sao, không chỉ ghi là có gì đó đã bắn."

**Mẹo:** so với Delivery A9.1 và Load A6.3 — mỗi stage một dạng pass sai, cùng một cách chống.

**A8.3** **Ý chính:** "Drill đã chạy và chứng minh đúng những thứ đó: page bắn từ cặp một giờ — 1h ở 14.66 và 5m ở
99.43, cả hai vượt 13.44 — và tới Discord sau 9 phút 30, với thời gian chia theo từng phần: 45 giây scrape, 15 giây
recording rule, 8 phút số học cửa sổ.

Và nó vẫn không chứng minh ba điều, y như tôi viết ra trước khi chạy. SLO đạt trong bất kỳ chu kỳ nào — không bao giờ,
trên một cụm bị huỷ khi không dùng. Rằng mọi cặp dài cư xử như *guide* trông đợi: cặp 6h/30m không bắn, chân 6h
đứng ở 5.30 dưới ngưỡng 5.6 — nhưng đó là cặp ấy làm **đúng** việc của nó, không phải nó hỏng. Store đã 9.67 giờ tuổi
nên cửa sổ 6 giờ có đủ dữ liệu, và mẫu số lớn đó cần khoảng hai mươi phút mới đẩy một lỗi 50% qua 5.6. Guide đã được
sửa, với 5.30 ghi lại làm lý do. Cái *thật* chưa được hiệu chuẩn trên nền tảng này là hai cặp ticket 1d/2h và 3d/6h,
có cửa sổ dài hơn tuổi của store: chúng giữ nguyên ngưỡng mà đánh giá trên một quãng ngắn hơn cái tên nó mang. Và rằng page sẽ
tới được giữa hai drill — không có dead-man's-switch nào, nên không.

Một điều drill *có* chứng minh mà tôi không trông đợi: alert tự tắt, và tắt chậm hơn lúc bắn — 26 phút so với 9."

### A9. Giới hạn và nhìn lại

**A9.1** **Ý chính:** "Không có dead-man's switch — webhook hỏng thì im lặng cho tới drill sau. Discord là đường
gửi duy nhất, và nó đi ra qua NAT gateway duy nhất, nên mất zone đó là mất cả service lẫn kênh báo. Các cặp
ticket chưa bao giờ được hiệu chỉnh trên nền tảng này. Và Prometheus với Alertmanager không có đăng nhập, nên ai
trên VPN cũng tắt được một page."

**A9.2** **Ý chính:** "Một dead-man's switch thật, gửi heartbeat ra một dịch vụ bên ngoài. Một công cụ trực thật,
có lịch trực, và một hệ thống ticket thật. Một error budget policy — hết ngân sách thì dừng release. Metric sống
lâu dài để các cặp dài được hiệu chỉnh và SLO đo được thật. Và đăng nhập cho Alertmanager."

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)

---

### A10. Câu đào sâu — runbook, và ai canh người canh

**A10.1** **Ý chính:** "Mỗi alert có `runbook_url` trỏ vào một mục trong `docs/runbooks/anime-api.md`, và nó được viết
*trước* drill đầu tiên bắn alert đó. Bốn bước, chạy trên ops. Một: nó có thật không và nặng đến đâu — đọc tỉ lệ theo
`status`, rồi đọc thẳng burn rate hiện tại. Hai: **stage nào hỏng** — `anime_upstream_errors_total` có nhãn `stage`,
nên `llm` là provider đang hỏng hoặc hết quota, `retrieval` là embedding hoặc index; nếu không cái nào mà 5xx vẫn
tăng thì lỗi nằm trong chính api và tôi đọc traceback. Ba: **vừa có gì đổi không** — canary đang chạy thì phân tích
phải chặn nó, chưa chặn thì tôi abort tay; vừa promote thì revert **trong Git**, không sửa tay, vì self-heal sẽ xoá
bản sửa tay; và `FAULT_RATE` khác 0 nghĩa là một drill còn nằm đó. Bốn: capacity — pod không Ready hoặc đang restart
thì cũng làm lỗi request."

*Nếu được hỏi thêm:* runbook mở đầu bằng hai câu tôi cho là quan trọng nhất. Một, page nghĩa là gì bằng thời gian:
với burn 13.44 thì budget 28 ngày hết trong khoảng **hai ngày**, với 5.6 thì khoảng năm ngày — "look now" so với
"look this week". Hai, một cảnh báo riêng cho nền tảng này: store của Prometheus chỉ vài tiếng tuổi, nên **mọi cặp
trừ 1h/5m đều tính trên ít dữ liệu hơn cái tên nó mang** — phải đọc burn rate từng cửa sổ trước khi tin cặp nào đã
bắn.

Và một điều runbook giờ đã ghi, từ phép đo: **page sẽ không tắt cùng lúc với bản sửa.** Drill đo được 26 phút 06,
do cặp 6h/30m giữ. Người vận hành chờ nó tắt ngay sẽ kết luận bản sửa không ăn và đi tìm một sự cố thứ hai không
tồn tại.

**Mẹo:** "một alert tới mà không kèm hướng dẫn thì là một lần bị ngắt, không phải một tín hiệu" — câu đó ở đầu
runbook, nói ra được thì rất gọn.

**A10.2** **Ý chính:** "Hôm nay thì tôi **không biết**, và đó là lỗ hổng tôi nói thẳng. Không có Watchdog, không có
dead-man's-switch. Prometheus chết thì không có gì bắn, và trên nền tảng này còn tệ hơn: cụm bị huỷ khi không dùng,
nên một store trống là trạng thái *bình thường* mỗi sáng chứ không phải dấu hiệu bất thường."

*Nếu được hỏi thêm:* lập luận cho việc phải có dead-man's-switch nằm ngay trong bằng chứng của tôi, ở chỗ khác. Tôi
đã chứng minh rằng **một cửa sổ rỗng trả về "không có dữ liệu", không phải "không có lỗi"** — đó là lý do KEDA đặt
`ignoreNullValues=false`, và là lý do phép đếm rò Langfuse phải đo một trace đáng ra phải xuất hiện *trước*. Cùng lập
luận đó áp cho đường alert thì kết luận là: phải có một alert luôn luôn bắn, và cái im lặng mới là thứ gọi người.

Cái tôi *đã* làm là hai thứ nhỏ hơn. Một phép kiểm lúc bắt đầu phiên, khẳng định store có đủ dữ liệu cho từng cửa sổ
trước khi tin cặp nào. Và các ticket burn chậm được dán nhãn **chưa hiệu chuẩn** trên nền tảng này thay vì được trích
như số đo. Với một hệ thật thì thứ tự tôi thêm là: Watchdog ra một dịch vụ ngoài cụm, rồi alert trên chính đường
alert — `ALERTS{alertname="Watchdog"}` mất tích trong năm phút là một page.

**Mẹo:** câu này rất hay bị hỏi sau khi bạn kể xong 9 phút 30. Trả lời "hôm nay tôi không biết" rồi đưa ra lập luận
mình đã dùng ở chỗ khác thì mạnh hơn hẳn việc mô tả một giải pháp mình chưa dựng.
