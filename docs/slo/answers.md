# Đáp án SLO

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Load A3.4` trỏ tới bộ tương ứng.

Stage này **mới thiết kế, chưa chạy**. Mọi câu ở thì hiện tại bên dưới nói về thiết kế, và câu đầu tiên của A1.1
nói rõ điều đó một lần. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **cặp** cho một cửa sổ dài ghép với một cửa sổ ngắn (cặp 1h/5m); **page**
cho alert gọi người ngay; **ticket** cho alert để xử lý trong vài ngày tới; **drill** cho lần cố ý tiêm lỗi để kiểm
alert.

**Số liệu đã có:** chưa có số nào cho stage này. Các hệ số, và mọi con số phút ở A5.2, A6.2 và A6.3, là **tính
toán** — nói rõ như vậy khi dùng.

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| T | Lần chạy baseline ở stage Load | A2.1 |
| Time-to-alert theo từng phần, `alertname`, severity, SLO, burn của từng cửa sổ lúc bắn, lượng traffic sạch trước đó | Drill alert | A1.1, A6.5 |
| Giá trị thật của chu kỳ scrape, chu kỳ đánh giá rule, `group_wait`, `group_interval` | Cấu hình chart | A6.5 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi mới thiết kế, chưa chạy. Có hai SLO trên route chính của api: availability 99.5%,
và 95% request dưới T — T đo ở stage Load. Mọi alert là ngưỡng trên burn rate, mỗi alert xét hai cửa sổ cùng lúc. Cặp
nhanh gọi người, cặp chậm mở ticket. Rule do Sloth sinh ra với hệ số cho chu kỳ 28 ngày, và được commit vào Git. Và tôi
nói thẳng: một nền tảng sống vài giờ mỗi ngày không bao giờ chứng minh được SLO đạt. Thứ nó chứng minh được là alert bắn
đúng rule và tới được người."

*Nếu được hỏi thêm:* drill cho kết quả `[điền: time-to-alert theo từng phần, alertname, severity, SLO, burn từng cửa sổ,
lượng traffic sạch trước đó]`.

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
bắt ở SLO availability. T là `[điền: T]`.

**A2.2** **Ý chính:** "Burn rate là tốc độ tiêu ngân sách, so với việc tiêu vừa khít trong cả chu kỳ. Burn rate 1 thì ngân
sách dùng đúng hết chu kỳ; burn rate n thì hết trong 1/n chu kỳ. Alert trên burn rate vì cùng một tỉ lệ lỗi mang nghĩa rất
khác với các SLO khác nhau. Burn rate chuẩn hoá điều đó, nên một kiểu alert dùng được cho mọi SLO, và mọi ngưỡng đọc thành
'bao lâu nữa thì hết ngân sách'."

**A2.3** **Ý chính:** "SLO latency dựng từ T. Một SLO có ngưỡng đoán mò sinh ra một ngân sách đoán mò, và mọi alert trên đó
thừa hưởng phỏng đoán. Còn một chi tiết kỹ thuật: SLI đếm counter tại `le=T`, nên T phải là một ranh giới bucket, nếu không
query trả về rỗng và alert không bao giờ bắn."

*Nếu được hỏi thêm:* `le` là một chuỗi, nên cách viết con số cũng phải khớp **[kiểm chứng]**; bucket không tồn tại thì cả
biểu thức rỗng. Chi tiết ở Load A3.4.

**A2.4** **Ý chính:** "Nó là một định nghĩa, không phải thứ đo được. Không cửa sổ 28 ngày nào tồn tại ở đây. Chu kỳ đó quyết
định kích thước ngân sách, và từ đó quyết định các ngưỡng alert. Không có gì trong project này sẽ tuyên bố SLO đã đạt."

*Nếu được hỏi thêm:* vì sao 99.5% thì design không ghi lý do. Quan điểm của tôi: trên 28 ngày nó cho khoảng 3.4 giờ lỗi, và
service dựa vào tier miễn phí của Gemini và Hugging Face thì không thể hứa chặt hơn thứ nó phụ thuộc vào.

### A3. Hai cửa sổ, hai tốc độ

**A3.1** **Ý chính:** "Cửa sổ dài hỏi: burn này có thật, không phải một cú giật? Cửa sổ ngắn, dài khoảng một phần mười hai,
hỏi: nó còn đang xảy ra không? Alert chỉ bắn khi cả hai vượt ngưỡng. Chỉ cửa sổ dài thì chậm bắt đầu, và sau một đợt burn lớn
thì chậm dừng. Chỉ cửa sổ ngắn thì bắn theo mọi cú giật. Ghép lại thì nhanh theo cả hai chiều."

**A3.2** **Ý chính:** "Page làm gián đoạn một người ngay bây giờ; ticket là việc cho vài ngày tới. Hai cặp nhanh — 1h/5m và
6h/30m — page, vì với tốc độ đó ngân sách hết trong vài ngày. Hai cặp chậm — 1d/2h và 3d/6h — mở ticket: một lỗi rỉ rả đáng
sửa, nhưng không đáng đánh thức ai. Page tới kênh #alerts, ticket tới kênh #tickets."

*Nếu được hỏi thêm:* "ticket" ở đây chỉ là một tin nhắn vào kênh #tickets, không phải một hệ thống ticket thật. Route gốc
giữ receiver rỗng của chart, nên alert nào không khớp hai route đó thì không đi đâu cả.

**A3.3** **Ý chính:** "Mỗi hệ số là phần ngân sách mà nếu bị tiêu trong cửa sổ dài thì alert bắn, nhân chu kỳ, chia cửa sổ.
2% ngân sách của 672 giờ, trên một giờ, là 13.44. 5% trên sáu giờ là 5.6. 10% trên một ngày là 2.8. 10% trên ba ngày là
khoảng 0.93. Các con số quen thuộc 14.4, 6, 3, 1 là cùng các phần đó trên 720 giờ — chu kỳ 30 ngày."

*Nếu được hỏi thêm:* Sloth tự tính bộ cho 28 ngày khi được chạy với chu kỳ 28 ngày. Mặc định của nó là 30 ngày, nên chu kỳ
phải nằm cả trong lệnh CI chạy lại, nếu không rule đã commit lặng lẽ mang hệ số 30 ngày **[kiểm chứng]**.

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

**A5.2** **Ý chính:** "Chỉ cặp 1h/5m được hiệu chỉnh cho phần lớn một phiên. Nhưng Sloth gộp hai cặp page vào
cùng một alert bằng phép `or` **[kiểm chứng]**, nên tôi không chọn được cặp — cặp nào vượt ngưỡng trước thì bắn.
Theo tính toán, nếu Prometheus chỉ chứa một giờ traffic sạch, nhánh 6h/30m vượt ngưỡng sau khoảng bốn phút, sớm
hơn tám phút của cặp 1h/5m. Nên drill chạy khoảng ba giờ traffic sạch trước, để cặp 1h/5m về trước, và ghi lại
burn của từng cửa sổ lúc page bắn. Cặp nào bắn là điều tôi đọc ra, không phải điều tôi đoán từ tên alert."

*Nếu được hỏi thêm:* với ba giờ sạch, cửa sổ sáu giờ cần khoảng mười một phút — cặp một giờ thắng với khoảng cách
vài phút, cũng là tính toán. Hai cặp ticket vượt ngưỡng trong vài phút đầu dù thế nào, vào kênh #tickets, và được
ghi là chưa hiệu chỉnh.

**Mẹo:** đây là chỗ mà chính việc rà lại thiết kế đã tìm ra lỗi. Kể được "ban đầu tôi nghĩ một giờ sạch là đủ, tính lại thì
không" là một câu chuyện tốt.

### A6. Drill

**A6.1** **Ý chính:** "Một bản ở chế độ fake với 50% lỗi, promote thẳng lên toàn bộ traffic, sau khoảng ba giờ
traffic sạch. Rồi đo thời gian tới khi page tới Discord, chia theo từng phần, và ghi `alertname`, severity, SLO
và burn của từng cửa sổ."

*Nếu được hỏi thêm:* bản đó phải ghim cả `LLM_PROVIDER=fake`, vì tỉ lệ lỗi chỉ được fake provider đọc — Delivery
A8.2. Tên alert của page và ticket có thể giống nhau, chỉ khác label severity **[kiểm chứng]** — nên tên alert
một mình không đủ.

**A6.2** **Ý chính:** "Vì alert đọc tỉ lệ lỗi của cả service. Ở mức canary 10%, 50% lỗi thành 5% tổng — burn rate
10. Như vậy dưới ngưỡng 13.44 của cặp 1h/5m, nên cặp đó không bao giờ bắn; cặp 6h/30m với ngưỡng 5.6 chỉ bắn sau
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
chờ thêm, nên nó bắn luôn **[kiểm chứng]**; thời gian gom nhóm của Alertmanager; và thời gian Discord gửi. Chỉ
phần số học cửa sổ là về SLO; phần còn lại là cấu hình. Ghi từng phần mới biến 'từ lỗi tới tin nhắn mất X phút'
thành thứ có thể làm nhanh hơn."

*Nếu được hỏi thêm:* thời gian chờ của Alertmanager khác nhau tuỳ alert mở một nhóm mới hay nhập vào một nhóm đã
gửi rồi. Thời gian từ lệnh promote tới khi pod lỗi gánh toàn bộ traffic cũng nằm trong tổng. Các giá trị cấu hình
`[điền: chu kỳ scrape, chu kỳ đánh giá, group_wait, group_interval]`, kết quả `[điền: time-to-alert theo từng
phần]`.

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

**A8.3** **Ý chính:** "Khi drill chạy xong, stage này sẽ chứng minh: page bắn từ cặp một giờ và tới Discord, thời
gian được chia theo từng phần, và loại lần chạy — nhận ra hay gửi — được ghi rõ. Nó nói rõ là không chứng minh:
SLO đạt trong bất kỳ chu kỳ nào; các cặp dài cư xử đúng như thiết kế trên một Prometheus mới chạy vài giờ; và
page sẽ tới được giữa hai drill."

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
