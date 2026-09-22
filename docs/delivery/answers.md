# Đáp án Progressive delivery

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Load A3.5` trỏ tới bộ tương ứng.

Stage này **mới thiết kế, chưa chạy**. Mọi câu ở thì hiện tại bên dưới nói về thiết kế, và câu đầu tiên của A1.1
nói rõ điều đó một lần. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **gate** cho một điều kiện trong phân tích (gate tỉ lệ thành công, gate
latency); **lần đo** cho một measurement; **hash** cho label `rollouts-pod-template-hash`; **drill** cho lần cố ý chạy
promote hay rollback để lấy bằng chứng.

**Số liệu đã có:** chưa có số nào cho stage này. Các hệ số 1.43 và 1.22, và các mốc thời gian dự kiến ở A2.2, là
**tính toán** — nói rõ như vậy khi dùng.

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| Timeline của Rollout; giá trị từng lần đo và hash canary của nó, ở mỗi mức | Drill promote | A1.3 |
| Thời gian từ lúc bắt đầu tới lúc abort, lần đo thất bại, tỉ lệ request bị lỗi khi canary chạy | Drill rollback | A1.3, A8.1 |
| Tỉ lệ lỗi của canary trước khi abort | Drill rollback | A8.2 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi mới thiết kế, chưa chạy. API chuyển từ Deployment sang Rollout. Bản mới nhận 10%
traffic, chờ, được đo, rồi 50%, rồi 100%. Ở mỗi mức, một phân tích hỏi Prometheus hai câu: tỉ lệ thành công của canary
có đạt ít nhất 99% không, và p95 của nó có vượt 1.2 lần p95 của bản stable trong cùng khoảng thời gian không. Phần khó
không phải là quyết định. Phần khó là bảo đảm con số được đọc đúng là của canary, và ngưỡng viết trên giấy đúng là
ngưỡng đang có hiệu lực."

*Nếu được hỏi thêm:* chỉ API là Rollout; UI vẫn là Deployment và ra bản không qua phân tích. Con số của canary ở A4.1,
ngưỡng thật ở A5.1, quá ít bằng chứng ở A6.2.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "thiết kế, chưa chạy", rồi trình bày tự nhiên.

**A1.2** **Ý chính:** "Merge xong là cụm nhận bản mới mà không người nào đứng giữa. API còn là Deployment, nên image mới
thay mọi pod nhanh nhất có thể. Dấu hiệu đầu tiên của một bản lỗi sẽ là mọi người dùng đều gặp nó."

**A1.3** **Ý chính:** "#8: một bản tốt đi qua 10, 50, 100 — bằng chứng là timeline của Rollout và giá trị đo của từng
AnalysisRun, kèm hash của canary. #9: một bản ở chế độ fake với tỉ lệ lỗi 20% tự abort — bằng chứng là thời gian tới
lúc abort, lần đo thất bại, và tỉ lệ request bị lỗi khi canary chạy."

*Nếu được hỏi thêm:* kết quả `[điền: timeline, giá trị từng lần đo và hash]` và `[điền: thời gian tới abort, lần đo
thất bại, tỉ lệ request lỗi]`.

### A2. Release theo từng lát

**A2.1** **Ý chính:** "Rolling update của Deployment chỉ biết pod có Ready không. Một bản khởi động sạch rồi làm hỏng một
phần request, với Deployment, vẫn là một lần release thành công. Rollout vẫn quản lý ReplicaSet như Deployment, nhưng đi
theo một chiến lược viết sẵn — bước, chờ, phân tích — và có thể tự dừng hay tự lùi."

**A2.2** **Ý chính:** "Đặt trọng số 10%, chờ hai phút, phân tích; 50%, chờ hai phút, phân tích; rồi 100%. Phân tích là một
bước nằm trong chuỗi: Rollout chờ nó xong mới đi tiếp. Việc chờ trước khi đo để cửa sổ đầu tiên được lấp đầy bằng traffic
ở trọng số mới. Đo ngay sau khi chuyển thì con số chủ yếu mô tả traffic cũ."

*Nếu được hỏi thêm:* lần đo đầu chạy ngay, rồi cách 30 giây, nên bốn lần đo rơi vào giây 0, 30, 60 và 90. Tính ra, mỗi mức
mất khoảng ba phút rưỡi, và drill rollback nên abort khoảng hai phút rưỡi sau khi chuyển sang 10% **[kiểm chứng]**.

**A2.3** **Ý chính:** "Vì như vậy tỉ lệ là tỉ lệ *request*, không phải tỉ lệ pod. Không có router thì một pod mới cạnh
hai pod cũ nhận một phần ba traffic, bất kể bước đó ghi gì — tỉ lệ trở thành tác dụng phụ của việc scale, chứ không phải
một quyết định. Ở đây có hai Service riêng cho stable và canary, mỗi cái trỏ tới một target group. Argo Rollouts ghi trọng
số vào Ingress public, và controller load balancer áp nó lên listener."

*Nếu được hỏi thêm:* vì thế controller load balancer nằm trên đường đi của mọi lần release — GitOps A3.3. Target là IP
cũng để Argo Rollouts kiểm lại được trọng số trên target group có đúng như nó yêu cầu không.

**A2.4** **Ý chính:** "Thêm. Canary được scale theo trọng số nhân với số replica, làm tròn lên, còn stable giữ nguyên kích
thước, để một lần abort trả được toàn bộ traffic về ngay. Với hai replica, mức 10% đã thêm nguyên một pod. Tôi giữ mặc
định an toàn đó, nhưng nó là capacity được request thêm, và autoscaler của node sẽ thấy nó."

*Nếu được hỏi thêm:* có một hệ quả cho gate tương đối. Ở mức 50% với hai replica, một pod canary gánh một nửa traffic,
còn mỗi pod stable gánh một phần tư — gate latency so một pod chịu tải gấp đôi. Thiết kế chưa nói tới điểm này.

### A3. So với bản cũ, không so với mục tiêu

**A3.1** **Ý chính:** "Gate tỉ lệ thành công của canary, sàn 99%, chỉ đọc hash của canary. Và gate latency: p95 của canary
chia cho p95 của stable trong cùng cửa sổ, không được vượt 1.2 — đọc cả hai hash. Mỗi lần phân tích đo bốn lần, cách nhau
30 giây. failureLimit là 1: một lần đo thất bại được bỏ qua, lần thứ hai thì phân tích thất bại."

*Nếu được hỏi thêm:* có thêm một ngưỡng tối thiểu: dưới 20 request trong cửa sổ thì kết quả là inconclusive — A6.2. Ngưỡng
đó phải nằm trong điều kiện của từng gate, không phải một metric riêng; nếu tách riêng, gate tỉ lệ thành công vẫn có thể
thất bại trên dữ liệu mỏng **[kiểm chứng]**.

**A3.2** **Ý chính:** "Bắt buộc chứ không phải sở thích. T đo với model thật, còn drill chạy fake provider, mà latency
của fake chỉ bằng một phần của bất kỳ T hợp lý nào. Một gate tuyệt đối theo T sẽ để lọt một bản chậm hơn đáng kể. Tỉ lệ
giữa hai bản đo cạnh nhau hỏi một câu có nghĩa ở cả hai chế độ: bản mới có tệ hơn bản nó thay thế không?"

**A3.3** **Ý chính:** "Nó loại được những gì ảnh hưởng cả hai bản cùng lúc — ví dụ một buổi chiều provider chậm. Nó
không loại được những gì chỉ ảnh hưởng một bên: ở mức 10%, canary thường là một pod trên một node, và rắc rối của node đó
là của riêng canary."

*Nếu được hỏi thêm:* thiết kế chưa có quy tắc nào giữ pod canary khác node với stable. Đó là một khoảng hở đã biết.

### A4. Con số phải là của canary

**A4.1** **Ý chính:** "Chỉ bằng hash — label mà mỗi ReplicaSet gắn lên pod của nó. Nhưng label của pod không nằm trên
series nào cho tới khi lần scrape chép nó sang. PodMonitor làm việc đó. Query tỉ lệ thành công lọc theo hash của canary;
query latency đọc cả hai hash."

*Nếu được hỏi thêm:* vì sao là PodMonitor — Load A2.4.

**A4.2** **Ý chính:** "Query trả về rỗng, và mỗi lần đo báo lỗi. Quá giới hạn lỗi liên tiếp — mặc định là bốn — AnalysisRun
kết thúc ở trạng thái Error, và Rollout abort y như khi thất bại **[kiểm chứng]**. Nghĩa là một lỗi đường ống không lặng lẽ
promote bản xấu. Nó abort *mọi* bản, ồn ào, và mỗi lần abort trông như lỗi của bản mới."

**A4.3** **Ý chính:** "Khi mọi release đều bị abort, sẽ có người 'sửa' phân tích: cho query trả về không khi không tìm thấy
gì, hoặc viết điều kiện chấp nhận kết quả rỗng. Abort dừng lại. Và từ lúc đó một query rỗng có thể thành pass — rõ nhất ở
gate latency, vì không luôn nhỏ hơn 1.2 lần. Lỗi vô tình thì ồn ào; lỗi do người tạo ra để dập lỗi vô tình mới là lỗi im
lặng. Câu trả lời đúng cho query rỗng không phải pass cũng không phải abort, mà là dừng lại chờ người."

**Mẹo:** câu "lỗi nguy hiểm là lỗi do người tạo ra để dập lỗi đầu tiên" là câu đáng nhớ nhất của stage này.

**A4.4** **Ý chính:** "Có. Một filter chọn nhầm hash của *stable* trả về một con số khoẻ mạnh, khác rỗng, và promote một
canary hỏng. Một cách khác, nếu monitor là ServiceMonitor chọn trúng nhiều Service: mỗi pod bị scrape một lần cho mỗi
Service, số request nhân lên, và ngưỡng tối thiểu pass với một phần nhỏ số traffic nó đòi. Nên #8 đòi lần đo được ghi lại
phải khác rỗng *và* mang đúng hash của ReplicaSet canary."

**A4.5** **Ý chính:** "Vì `rate()` cần ít nhất hai mẫu trong cửa sổ, và Prometheus scrape mỗi 30 giây. Một cửa sổ 30 giây
thường chỉ có một mẫu, trả về rỗng — lỗi nằm ở phép tính, không phải ở release. Bốn chu kỳ scrape là mức sàn thường dùng.
Bốn lần đo cách nhau 30 giây, mỗi lần nhìn lại hai phút, nên các lần đo chồng lên nhau."

### A5. Ngưỡng trên giấy và ngưỡng thật

**A5.1** **Ý chính:** "Vì p95 của mỗi bản là *ước lượng* từ bucket, và ước lượng không vượt được một ranh giới bucket cho
tới khi đủ nhiều request vượt nó. Với latency của fake provider và bucket hiện tại, p95 ước lượng của stable nằm ngay dưới
ranh giới 2 giây, còn 1.2 lần của nó rơi ngay trên. Canary bị ghim ở ranh giới đó cho tới khi nó tệ hơn nhiều. Tính ra,
gate viết là 1.2 lần thực tế chỉ bắn ở khoảng 1.43 lần — một bản chậm hơn 40% vẫn lọt. Bucket dày hơn đưa nó về khoảng
1.22 lần."

*Nếu được hỏi thêm:* đây là tính toán, không phải số đo; nó giả định canary chậm đều theo một hệ số. Thay đổi bucket được
lên kế hoạch trước stage Load, nên nếu nó vào đúng hạn thì lúc chạy delivery gate là khoảng 1.22 lần — cũng là tính toán.
Chỉ một drill với một bản cố ý *chậm hơn* — không phải bản lỗi — mới đo được độ nhạy thật, và drill đó không nằm trong
tiêu chí. Bucket ở Load A3.5.

**Mẹo:** tự nói ra "đây là tính toán, không phải số đo" trước khi bị hỏi.

**A5.2** **Ý chính:** "Trên sáu mươi request, một lỗi đã dưới 99%. Vì mỗi lần đo nhìn lại một cửa sổ dài hơn khoảng cách
giữa các lần đo, một lỗi đó được vài lần đo liên tiếp đếm lại, và chỉ cần hai lần đo thấy nó là vượt failureLimit 1 —
phân tích thất bại. Một gate abort release khoẻ vì một lỗi lạc là gate mà mọi người sẽ học cách tắt đi."

**A5.3** **Ý chính:** "Không. Ngay cả 5 request mỗi giây cũng cho canary khoảng 60 request mỗi cửa sổ, dư sức vượt 20. Thứ
quyết định là độ phân giải của gate tỉ lệ thành công. Ở 20 request mỗi giây, mức 10% cho canary khoảng 2 request mỗi giây,
khoảng 240 request mỗi cửa sổ. Ở 99%, 240 request chịu được hai lỗi; 60 request thì trượt ngay lỗi đầu tiên."

**A5.4** **Ý chính:** "Một ngưỡng là một khẳng định về dụng cụ đo cũng nhiều như về service. Phải kiểm dụng cụ phân giải
được tới đâu trước khi tin vào con số ngưỡng được đặt."

### A6. Quá ít bằng chứng thì dừng

**A6.1** **Ý chính:** "Từng lần đo có thể Successful, Failed, Inconclusive hoặc Error. Cả AnalysisRun cũng kết thúc ở một
trong bốn trạng thái đó. Successful thì sang mức kế. Failed khi số lần đo thất bại vượt failureLimit, Error khi lỗi liên
tiếp vượt giới hạn — cả hai đều làm Rollout abort. Inconclusive thì Rollout dừng chờ người. Và một lần đo chỉ inconclusive
khi template viết cả điều kiện success lẫn failure mà không điều kiện nào khớp **[kiểm chứng]**."

**A6.2** **Ý chính:** "Ít quá — dưới 20 request trong cửa sổ — là inconclusive theo thiết kế: rollout dừng chờ người, không
bao giờ promote trên sự im lặng. 'Không lỗi nào trong bốn request' không phải bằng chứng. Còn *không có series* nào của
canary thì khác: không phải số không mà là kết quả rỗng, và rỗng thì lần đo báo lỗi chứ không dừng. Nên cả hai điều kiện
success và failure đều phải đòi kết quả khác rỗng trước khi so, để kết quả rỗng không khớp điều kiện nào."

*Nếu được hỏi thêm:* không có request mà series vẫn còn thì query đếm trả về không, và ngưỡng tối thiểu bắt được. Còn tỉ lệ
thì ra NaN — không chia được — và cũng phải được điều kiện xử lý **[kiểm chứng]**.

**A6.3** **Ý chính:** "Nếu Spot lấy node duy nhất của canary, mẫu của nó có thể trôi khỏi cửa sổ và query trở thành rỗng.
Không có quy tắc riêng thì lần đo báo lỗi, và release có thể bị abort vì một sự kiện capacity. Argo Rollouts không có trường
riêng cho inconclusive, nên cả hai điều kiện đều đòi kết quả khác rỗng — rỗng không khớp điều kiện nào và thành
inconclusive. Cú pháp chính xác tôi sẽ kiểm lại theo đúng phiên bản **[kiểm chứng]**."

*Nếu được hỏi thêm:* rỗng chỉ xảy ra khi pod mới chưa kịp Ready và được scrape trong lúc mẫu của pod cũ đã trôi khỏi cửa
sổ hai phút. Một khoảng trống ngắn chỉ gây vài lần đo lỗi, chưa vượt giới hạn lỗi liên tiếp. Spot báo trước hai phút.

### A7. Sau khi abort

**A7.1** **Ý chính:** "Rollout đưa trọng số canary trên Ingress về không ngay, rồi scale canary về không sau một khoảng trễ
ngắn **[kiểm chứng]**. Stable giữ toàn bộ traffic, còn Git vẫn ghi digest mới. Argo CD hiện nó là Synced nhưng Degraded —
sự bất đồng nằm ở health, không nằm ở trạng thái sync. Đó là lúc Git cố ý không mô tả thứ đang chạy, kéo dài cho tới khi
có người sửa, và nó nhìn thấy được. Đó là khác biệt giữa rollback và drift."

**A7.2** **Ý chính:** "Bằng Git: revert thay đổi, hoặc sửa nó. Revert về digest cũ thì hash quay về hash của stable, và
Rollout trở lại khoẻ mà không phải đi lại các mức canary **[kiểm chứng]**. Sync lại thì không làm gì, vì chẳng có gì lệch
sync. Cách sai là đẩy rollout qua bằng tay với lệnh promote toàn phần: nó xoá Degraded và ship đúng bản mà phân tích đã từ
chối, mà không ai quyết định bản đó ổn cả. Trạng thái Degraded tồn tại chính để bắt người ta nghĩ lại trước bước đó."

*Nếu được hỏi thêm:* lệnh retry là cách chạy lại hợp lệ — nó đi lại các mức và chạy lại phân tích.

### A8. Drill

**A8.1** **Ý chính:** "Cả hai đều chạy với toàn bộ api ở chế độ fake, để hai bản được so trên cùng điều kiện, với k6 giữ 20
request mỗi giây. Drill promote: một bản mới từ CI đi qua 10, 50, 100, mỗi mức có lần đo được ghi lại. Drill rollback: cùng
như vậy, cộng `FAULT_RATE=0.2`. Theo thiết kế, phân tích sẽ thất bại ở mức 10% và Rollout abort, trả toàn bộ traffic về
stable."

*Nếu được hỏi thêm:* tính ra, canary lỗi khoảng 20% request của nó, tức khoảng 2% tổng traffic trong lúc nó chạy. Request
bị tiêm lỗi vẫn chờ đủ latency rồi mới trả 503, nên lỗi hiện ở gate tỉ lệ thành công, không phải gate latency. Ghi lại
`[điền: thời gian tới abort, lần đo thất bại, tỉ lệ request lỗi]`.

**A8.2** **Ý chính:** "Vì `FAULT_RATE` chỉ được fake provider đọc. Bản drill phải ghim cả `LLM_PROVIDER=fake`. Đặt tỉ lệ lỗi
lên một bản chạy Gemini thì không tiêm gì cả: canary khoẻ, phân tích pass, bản đó được promote — và drill được ghi là bằng
chứng rollback hoạt động. Một drill không tiêm gì mà vẫn ghi 'rollback chạy tốt' còn tệ hơn không có drill."

*Nếu được hỏi thêm:* tỉ lệ lỗi đo được của canary `[điền: tỉ lệ lỗi của canary trước khi abort]`.

**A8.3** **Ý chính:** "Không. Một image không pull được sẽ kẹt tới hết hạn tiến độ rồi thành Degraded — và chỉ abort nếu được
cấu hình như vậy; mặc định là không. Công lao đó không thuộc về phân tích. Bản ghi phải mang chính lần thất bại của
AnalysisRun."

### A9. Pass mà vẫn hỏng, và giới hạn

**A9.1** **Ý chính:** "Một quyết định dựa trên những con số không nói về thứ đang được quyết — hoặc dựa trên một ngưỡng không
phải là ngưỡng đã viết. Cách sửa lần nào cũng như nhau: ghi lại lần đo, hash của nó và giá trị của nó, không chỉ ghi kết quả
cuối."

**Mẹo:** so với Load A6.3 — ở Load con số đúng về thứ khác; ở đây quyết định dựa trên con số đó.

**A9.2** **Ý chính:** "Khi các drill chạy xong, stage này sẽ chứng minh: một bản tốt tới được toàn bộ traffic dựa trên lần đo
được ghi lại và thuộc về canary; một bản lỗi bị chính phân tích abort, với giá trị thất bại được ghi lại. Nó *tính ra* nhưng
không đo độ nhạy thật của gate latency. Muốn đo cần một drill với bản cố ý chậm hơn, và drill đó không nằm trong tiêu chí."

**A9.3** **Ý chính:** "Ba điều. Controller load balancer nằm trên đường đi của mọi release — nó không áp được trọng số thì
không gì di chuyển. Cho tới khi bucket đổi, gate latency lỏng hơn 1.2 lần rất nhiều. Và chỉ một người trả lời mọi lần dừng —
inconclusive chỉ an toàn nếu có người nhận ra nó. Thêm nữa, UI không có canary."

**A9.4** **Ý chính:** "Đưa lần dừng inconclusive thành một thông báo tới người trực, thay vì chờ ai đó mở dashboard. Rồi thêm
drill với một bản cố ý chậm hơn, để đo độ nhạy thật của gate latency thay vì chỉ tính."

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)
