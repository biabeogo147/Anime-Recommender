# Đáp án Scaling

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Load A4.5` trỏ tới bộ tương ứng.

Stage này **đã chạy**: criterion #14 — replica và node đi theo tải — **pass**, 2026-09-23
([evidence](../evidence/scaling.md)). Nói ở thì quá khứ được, nhưng chỉ với những gì evidence ghi. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **in-flight** cho số request đang được xử lý; **trigger** cho điều kiện KEDA
đọc; **điểm gãy** cho chỗ p95 tách khỏi p95 lúc tải thấp, đo ở stage Load; **scale out / scale in** cho thêm / bớt.

**Số liệu đã đo** ([`../evidence/scaling.md`](../evidence/scaling.md), 2026-09-23, fake mode, ramp tới **267
req/s** — gần 3 lần trần 93.9 req/s của hai pod — giữ mười phút):

| Đọc được | Giá trị | Dùng ở |
|---|---|---|
| Ngưỡng trigger | **30** in-flight mỗi pod — dưới 40, giới hạn thread pool | A2.2 |
| CPU / memory mỗi pod tại trần, thành resource request | 0.23 core / 143 MiB → request **250m / 256Mi** | A4.3 |
| Dự đoán viết **trước** khi chạy | node 1 còn 420m nhận 1 pod, node 2 còn 1090m nhận 4 → **7 pod vừa hai node, pod thứ 8 thì không** | A4.3 |
| Dự đoán đúng cả hai nửa | in-flight đo được 31–31.9 ở 7 replica, 27.7–28.9 ở 8; pod không xếp được đúng là pod thứ 8 | A4.3 |
| In-flight vượt 30 (đạt 32) | 13:24:33Z | A5.1 |
| **HPA 2 → 3** | 13:24:52Z, **+19 s** | A1.3, A5.1 |
| 3 → 4 → 5 → 6 → 7 | 13:25:50 … 13:29:26Z, một bước mỗi ~1 phút | A5.1 |
| **HPA đạt 8, một pod `Pending`** | 13:30:27Z, +5 m 35 s từ bước đầu | A1.3 |
| **Cluster Autoscaler: node 3 `Ready`** | 13:31:07Z, **+40 s** từ pod Pending | A1.3, A5.2 |
| Đủ 8 pod chạy, `pending` về 0 | 13:31:27Z, **+60 s** từ pod Pending | A5.2 |
| Lý do scheduler nêu | `Insufficient cpu` — không phải memory, đúng như phép tính | A4.3 |
| Node 3 tồn tại mà vẫn chưa nhận pod | `1 node(s) had untolerated taint(s)` — taint khởi tạo | A5.2, A8.3 |
| Toàn bộ ramp | **224396** request, **0** lỗi, p95 **1.44–1.47 s**, 0 iteration bị bỏ | A1.3 |
| So sánh: 2 pod cố định ở stage Load | p95 **15.6 s** — và ở 120 req/s, **dưới một nửa** tốc độ này | A1.3 |
| Lần giảm đầu, 8 → 7 | 13:45:14Z, **+5 m 12 s** — cửa sổ stabilisation 300 s của HPA | A5.3 |
| **Về `minReplicas` = 2** | 13:50:04Z, **10 m 02 s** từ lúc tải dừng | A1.3, A5.3 |
| **Node 3 bị xoá** | 13:56:37Z, **26 m 16 s** sau khi được thêm | A5.3 |
| Ra / về | **6 m 35 s** ra, **10 m 02 s** về | A5.3 |
| Scale-in dưới tải nhẹ 5 req/s | **4935** request, **0** lỗi, `available` không bao giờ dưới `desired` | A1.3 |
| Trigger động **trước** replica | chuỗi trigger 0 → 249 trước khi `desired` rời 2 | A6.1 |
| KEDA đọc Prometheus | `numberOfFailures: 0`, `Fallback=False` | A6.1 |

Con số `4` trong design chỉ là giá trị tạm, không phải ngưỡng — ngưỡng thật là 30.

| Chỗ còn trống | Vì sao | Dùng ở |
|---|---|---|
| Thời gian chờ Spot riêng lẻ | Không tách được khỏi 40 giây tới lúc node `Ready` | A8.3 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi đã chạy, criterion #14 pass. KEDA scale Rollout của api từ 2 tới 8 pod, theo số
request đang xử lý trung bình mỗi pod, ngưỡng 30 — dưới giới hạn 40 luồng của pod, để autoscaler phản ứng trước khi
hàng đợi hình thành. Ở 267 request mỗi giây, gần ba lần cái trần hai pod chịu được, nó lên đúng 8 pod trên 3 node và
người dùng không thấy gì: p95 giữ 1.44–1.47 giây qua 224396 request, không một request nào lỗi. Cluster Autoscaler thêm node, từ 2 tới 4,
khi có pod không còn chỗ chạy. Cả hai là vòng điều khiển có độ trễ, cả hai đọc những tín hiệu có thể biến mất. Và mỗi cái có
thể trông như đã chạy đúng trong khi cái kia thì không."

*Nếu được hỏi thêm:* KEDA scale được Rollout vì Rollout có subresource `/scale`, giống Deployment. UI không được autoscale.
Tín hiệu ở A2.1, khi tín hiệu biến mất ở A6.1, pod và node ở A4.1.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "đã chạy, criterion #14 pass", rồi trình bày tự
nhiên. Câu đáng nhớ nhất của stage này không phải "cụm đã scale" mà **"tải gấp ba mà không ai nhận ra"**.

**A1.2** **Ý chính:** "Request xếp hàng, latency tăng, và error budget bắt đầu bị đốt. Không có gì thêm capacity: số pod là
con số cố định ghi trong Git, bất kể traffic."

**A1.3** **Ý chính:** "Chạy lại lần ramp với ScaledObject và Cluster Autoscaler đang hoạt động: replica tăng dần
về 8, node về 4, rồi cả hai quay về. Bằng chứng là replica và node theo thời gian, giá trị của trigger, độ trễ
scale out của pod và của node tách riêng, thời điểm scale in của pod so với cửa sổ của HPA, và thời điểm bớt node
so với hai mốc mười phút của Cluster Autoscaler."

*Nếu được hỏi thêm:* trigger vượt 30 lúc 13:24:33Z; HPA 2 → 3 sau **19 giây**; lên 8 và có một pod `Pending` lúc
13:30:27Z; node thứ ba `Ready` **40 giây** sau đó và đủ 8 pod chạy sau **60 giây**. Về: lần giảm đầu sau **5 phút 12**
— cửa sổ stabilisation 300 giây — và về `minReplicas` 2 sau **10 phút 02**, node bị xoá **26 phút 16** sau khi được
thêm. Trigger chạy từ 0 lên 249 *trước khi* `desired` rời khỏi 2.

### A2. Tín hiệu và ngưỡng

**A2.1** **Ý chính:** "Vì request ở đây gần như chỉ chờ — chờ API embedding, chờ model. Một pod bận có CPU rảnh và một hàng
đợi phía sau. HPA theo CPU sẽ ngồi ở vài phần trăm trong khi request chồng chất, không bao giờ scale, và dashboard còn bảo
service đang được dùng ít. Số request đang xử lý mới là thứ tăng đúng lúc service đuối."

**A2.2** **Ý chính:** "Từ lần ramp ở stage Load: tại điểm gãy, lần chạy đó sẽ đọc thẳng từ gauge xem mỗi pod đang
giữ bao nhiêu request. Trigger được đặt thấp hơn con số đó một khoảng. Định luật Little — số request đang xử lý
bằng tốc độ đến nhân thời gian trung bình — là phép đối chiếu, để chắc con số đọc được khớp với tốc độ và latency
đo cùng lúc."

*Nếu được hỏi thêm:* dùng latency *trung bình*, không phải p95 — p95 thổi phồng số request một pod giữ. Và ở mép
một ramp đang tăng, hệ thống không hẳn ổn định, nên phép đối chiếu chỉ gần đúng; gauge mới là số đọc chính. Kết quả: ngưỡng trigger là **30**, và tôi *không* lấy nó từ in-flight tại điểm gãy — con số đó ra 170.5 rồi 117.5
ở hai lần ramp, lệch 45%, không tái lập. Ngưỡng lấy từ giới hạn kiến trúc mà nó đang thay mặt: 40 luồng mỗi pod. Khi
chạy, gauge đo được **31–31.9** in-flight mỗi pod ở 7 replica và **27.7–28.9** ở 8 — đúng hai bên ngưỡng 30, nên HPA
dừng ở `maxReplicas`.

**A2.3** **Ý chính:** "Vì tôi đo điểm gãy như một giới hạn về *đồng thời*, không phải về tốc độ. Một điểm gãy
tính bằng request mỗi giây không mang được từ chế độ fake sang chế độ thật, vì model thật chậm hơn nhiều lần. Còn
một giới hạn kiểu 'một pod giữ được tối đa bấy nhiêu request cùng lúc' thì không quan tâm mỗi request mất bao
lâu. Thread pool của api nhiều khả năng chính là giới hạn đó — nên ngưỡng được viết bằng in-flight chứ không bằng
tốc độ."

*Nếu được hỏi thêm:* "nhiều khả năng" là thật — nếu điểm gãy ở chế độ fake hoá ra là CPU chứ không phải thread pool, lập luận
này yếu đi, và bản ghi phải nói vậy. Load A4.6.

**A2.4** **Ý chính:** "Vì trigger dùng kiểu giá trị trung bình, nghĩa là HPA tự chia tổng cho số pod. Nếu query
đã chia rồi thì bị chia hai lần. Và fallback của KEDA chạy với kiểu trung bình đó — lý do thứ hai để giữ query là
một `sum` đơn giản **[kiểm chứng: fallback hỗ trợ những kiểu nào ở phiên bản KEDA được ghim]**."

### A3. Một vòng điều khiển có độ trễ

**A3.1** **Ý chính:** "Lần scrape kế tiếp đọc gauge. Lần sync kế tiếp của HPA — mặc định mười lăm giây — hỏi KEDA
lấy giá trị. Scheduler đặt pod mới; nếu không vừa node nào, pod Pending và phải chờ Cluster Autoscaler vài phút.
Rồi kéo image, khởi động, nạp index. Probe readiness pass, và load balancer đăng ký nó — readiness gate giữ
Rollout không tính nó là sẵn sàng cho tới khi load balancer đồng ý. Rồi hàng đợi mới giảm. Trong suốt các bước
đó, tải vẫn tiếp tục tăng."

*Nếu được hỏi thêm:* khoảng polling của KEDA chỉ lo việc đi từ không lên một và ngược lại; giữa các mức khác
không, HPA tự kéo giá trị từ KEDA khi cần.

**A3.2** **Ý chính:** "Vì khoảng cách giữa trigger và điểm gãy là thứ trả tiền cho mọi độ trễ ở trên. Đặt trigger
đúng điểm gãy thì mọi lần scale out đều tới muộn — capacity tới sau lúc cần nó."

**A3.3** **Ý chính:** "Hai điều. Hiện endpoint health và metrics còn chạy chung thread pool với request thật. Lúc
bão hoà, lần scrape và probe xếp hàng sau công việc: tín hiệu biến mất, và một pod đang bận bị đánh dấu không sẵn
sàng đúng ở điểm gãy. Thiết kế chuyển chúng thành `async def` trước lần ramp. Điều thứ hai: ở chế độ thật, pod
mới khởi động phải gọi API embedding. Nếu provider đó sập thì pod mới không bao giờ sẵn sàng, scale out đứng lại,
còn pod cũ vẫn chạy tiếp."

*Nếu được hỏi thêm:* Load A4.6.

### A4. Pod và node

**A4.1** **Ý chính:** "Autoscaler của pod chỉ thêm pod, không thêm được máy. Một pod mà request của nó không vừa
node nào thì nằm Pending. Cluster Autoscaler theo dõi những pod như vậy và nới node group. Nó bớt node khi tổng
request trên node thấp — mặc định dưới một nửa **[kiểm chứng]** — và pod trên đó dời được sang chỗ khác. Min và
max của một managed node group chỉ là giới hạn cho thứ khác di chuyển bên trong; tự chúng không làm gì. Không có
Cluster Autoscaler thì pod đầu tiên không còn vừa hai node sẽ Pending mãi."

*Nếu được hỏi thêm:* Cluster Autoscaler có Pod Identity riêng, chỉ được ghi vào Auto Scaling group của node group
này. EKS tự gắn tag cho Auto Scaling group của managed node group, nên Cluster Autoscaler tự tìm ra nó. Node group
chỉ có một loại instance, `m7i-flex.large` — loại 2 vCPU / 8 GiB duy nhất gói Free cho chạy
(`docs/evidence/account.md`) — nên khuôn mà Cluster Autoscaler dùng để giả lập node mới khớp đúng node thật.

**A4.2** **Ý chính:** "Chủ yếu là resource *request*, không phải mức dùng thật. Scheduler đặt pod theo thứ pod
xin, và Cluster Autoscaler thêm bớt node cũng theo đúng thước đo đó. Một pod xin ít thì vừa gần như mọi chỗ."

*Nếu được hỏi thêm:* ngoài request còn các ràng buộc xếp lịch — rải pod theo topology, hay giới hạn số pod mỗi node theo số
địa chỉ IP mà VPC CNI cấp được — cũng làm pod Pending **[kiểm chứng]**.

**A4.3** **Ý chính:** "Thì node không bao giờ cần thêm, và nửa node của #14 không xảy ra. Tôi sẽ không tăng
request để thấy nó xảy ra — như thế là tạo ra một đồ thị đẹp về một con số không ai đo. Request được đặt từ mức
một pod thật sự dùng tại điểm gãy. Nếu nó vừa, nửa node được ghi là *chưa được thử*, kèm lý do."

*Nếu được hỏi thêm:* tại trần, mỗi pod dùng **0.23 core** và **143 MiB**, nên resource request đặt 250m / 256Mi.
Và **tám pod không vừa hai node** — đó là dự đoán tôi viết ra trước khi chạy: node 1 còn 420m nhận thêm một pod rồi
170m còn lại không nhận nổi cái nào, node 2 còn 1090m nhận bốn, nên 7 pod vừa và pod thứ 8 thì không. Đúng cả hai
nửa, và scheduler nêu đúng lý do phép tính nêu: `Insufficient cpu`, không phải memory.

**Mẹo:** đây là câu thể hiện rõ sự trung thực của cả project. Người phỏng vấn thường thích nghe "tôi sẽ ghi là chưa thử" hơn
một đồ thị hoàn hảo.

**A4.4** **Ý chính:** "KEDA có thể đòi 8 pod, nhưng node group dừng ở 4 node. Một ramp có autoscaling mà đi ngang
có hai nguyên nhân: service bão hoà, hoặc cụm hết chỗ cho pod. Bằng chứng phải nói là cái nào — nên số pod *và*
số node đều được ghi theo thời gian."

### A5. Đi xuống

**A5.1** **Ý chính:** "Theo cửa sổ ổn định scale in của HPA bên dưới KEDA — mặc định năm phút, và ScaledObject
đặt nó một cách tường minh. `cooldownPeriod` của KEDA ở đây không làm gì: nó chỉ áp cho việc scale về không, mà
service này tối thiểu là hai. Nên #14 so thời điểm scale in với cửa sổ của HPA, không với một cooldown không bao
giờ áp dụng."

*Nếu được hỏi thêm:* ra nhanh, vào chậm — thêm capacity muộn thì người dùng chịu, bớt sớm thì một phút sau phải
scale out lại và trả lại toàn bộ độ trễ khởi động. Mặc định của HPA cho scale out không chờ, mỗi mười lăm giây
tăng được gấp đôi hoặc thêm bốn pod; sau cửa sổ scale in, ScaledObject chỉ cho bớt một pod mỗi phút, để scale in không
rút nhiều pod cùng lúc. Thời điểm quay về: lần giảm đầu 8 → 7 lúc 13:45:14Z, **5 phút 12** sau khi tải dừng — đúng cửa sổ stabilisation
300 giây — rồi về `minReplicas` 2 lúc 13:50:04Z, tổng **10 phút 02**.

**A5.2** **Ý chính:** "Theo một đồng hồ riêng của Cluster Autoscaler: nó chỉ bỏ một node sau khi node đó không
cần tới trong mười phút, và không trong mười phút sau một lần scale out — hai mốc đó bằng mặc định của Cluster
Autoscaler, nhưng được ghi tường minh trong cấu hình, vì #14 đo theo chúng. Node đang giữ pod có storage cục bộ có thể bị bỏ qua, trừ khi pod nói nó
được phép bị dời. `/tmp` của api là một `emptyDir`, nên pod api mang annotation cho phép dời, với giá trị là tên
volume."

*Nếu được hỏi thêm:* nên câu "hệ thống đã về mức tối thiểu" có hai câu trả lời, theo hai đồng hồ, và lần chạy
scaling báo cả hai. Không chỉ pod api: pod nào có `emptyDir` — Prometheus, repo-server của Argo CD — cũng có thể
chặn việc bớt node, và cờ mặc định cho việc đó đã đổi qua các phiên bản **[kiểm chứng]**. PodDisruptionBudget của
api khiến Cluster Autoscaler đuổi từng pod một. Lúc node quay về: node thứ ba bị xoá lúc 13:56:37Z, **26 phút 16** sau khi được thêm, và quan sát thấy hai node
lúc 13:56:45Z. Log của Cluster Autoscaler cho thấy nó *từ chối* bớt node trong lúc điều kiện còn đúng:
`cpu requested (91.19% of allocatable) is above the scale-down utilization threshold`.

**A5.3** **Ý chính:** "Đó là một chỗ design ban đầu bỏ sót, và tôi đã thêm vào. Bớt một pod là bỏ địa chỉ IP của
nó khỏi ALB, nhưng việc gỡ đăng ký mất thời gian, trong khi pod đã được bảo dừng. Không có một khoảng trễ nhỏ
trước khi dừng và một thời gian ân hạn dài hơn thời gian gỡ, mỗi lần scale in sẽ trả lỗi cho những request còn
đang trên đường — lỗi mà SLO sẽ đếm. Các con số cụ thể đặt khi viết chart **[kiểm chứng]**."

### A6. Khi tín hiệu biến mất

**A6.1** **Ý chính:** "Scaler Prometheus của KEDA mặc định coi kết quả rỗng là không. Series biến mất — monitor
hỏng, lần scrape bị timeout — thì autoscaler thấy không có request nào đang xử lý và scale về mức tối thiểu, giữa
lúc tải đang có. Tệ hơn, việc biến mất dễ xảy ra nhất đúng lúc bão hoà, khi lần scrape bị bỏ đói là thứ hỏng đầu
tiên."

*Nếu được hỏi thêm:* cửa sổ ổn định scale in che được một lần mất ngắn; nguy hiểm là khi mất lâu hơn cửa sổ. Còn
Prometheus sập hẳn thì query lỗi kết nối, không phải rỗng — đó đã là lỗi rồi.

**Mẹo:** "rỗng không phải là không" — đây là lần thứ tư ý đó xuất hiện, và lần này hậu quả là một sự cố thật.

**A6.2** **Ý chính:** "Hai phần, và phần thứ hai hay bị quên. Thứ nhất, kết quả rỗng được biến thành lỗi, nên HPA
giữ nguyên số replica trong lúc lỗi kéo dài. Thứ hai, nếu lỗi lặp lại quá ngưỡng, KEDA chuyển sang fallback — mà
một fallback kiểu 'chạy n replica' sẽ scale *xuống* n dễ như scale lên. Nên fallback được đặt chế độ giữ số hiện
tại nếu nó cao hơn. Tín hiệu biến mất thì phải giữ nguyên, không được dịch chuyển."

*Nếu được hỏi thêm:* cụ thể là `ignoreNullValues: false`, rồi `failureThreshold`, số replica fallback, và chế độ
`currentReplicasIfHigher` — chỉ có ở một số phiên bản KEDA, nên phiên bản được ghim lúc dựng **[kiểm chứng]**.
Còn một lỗ hổng: mất *một phần* series — scrape của một pod timeout — thì kết quả không rỗng, chỉ thấp đi, và
không phép kiểm nào bắt được. Chỉ cửa sổ scale in đỡ được, nếu lần mất ngắn hơn cửa sổ.

### A7. Scale cùng những thứ khác

**A7.1** **Ý chính:** "Rollout không chia replica giữa hai bản. Stable giữ đủ kích thước, canary được thêm lên
trên theo trọng số. Giữa một lần release có nhiều pod hơn hẳn số replica, và pod nào cũng xin tài nguyên. Nên một
lần scale out giữa lúc canary đòi Cluster Autoscaler thêm nhiều node hơn phép tính in-flight gợi ý. Traffic vẫn
chia theo trọng số của load balancer, nên *tỉ lệ* của canary không đổi."

*Nếu được hỏi thêm:* pod mới của cả hai bản cũng khởi động bên trong cửa sổ phân tích, với khởi động lạnh mà tỉ
lệ latency có thể thấy. Delivery A2.4.

**A7.2** **Ý chính:** "HPA do KEDA tạo ghi số replica của Rollout; Argo CD, với self-heal bật, sẽ ghi nó lại về
con số trong chart — hai bên giành nhau. Nên chart của api không khai `replicas` trên Rollout, hoặc Application
bỏ qua khác biệt ở trường đó. Đây cũng là một chỗ design ban đầu bỏ sót."

### A8. Pass mà vẫn hỏng

**A8.1** **Ý chính:** "Bốn cách. Replica tăng vì một lần deploy xoay pod chứ không phải vì trigger bắn — nên phải
ghi giá trị trigger. Một lần chạy thấy scale out mà không bao giờ scale in, che một ScaledObject bị kẹt. Pod tăng
trong khi node không tăng, pod thừa nằm Pending — nhìn số replica thì tưởng thành công. Và một lần scale in do
query rỗng chứ không do tải giảm."

**A8.2** **Ý chính:** "Một nửa của một hệ thống hai phần chạy đúng, được báo cáo như cả hệ thống — pod tăng trong
khi node không tăng được, scale in đến từ một tín hiệu mất chứ không từ tải giảm, việc quay về mức tối thiểu được
tính giờ theo một thiết lập không bao giờ áp dụng."

**Mẹo:** so với SLO A8.2 và Delivery A9.1 — mỗi stage một dạng pass sai, cùng một cách chống: ghi cái gì đã xảy ra và vì sao.

**A8.3** **Ý chính:** "Stage này đã chứng minh cả hai nửa: dưới tải tăng, api tự thêm replica theo tín hiệu của
chính nó — và tôi chứng minh được là *của chính nó*, vì chuỗi trigger đi từ 0 lên 249 trước khi số replica mong muốn
rời khỏi 2 — rồi quay về mức tối thiểu sau đó. Node cũng được thêm và bớt, với từng độ trễ ghi lại: 40 giây tới lúc
node `Ready`, 60 giây tới lúc pod chạy được trên nó, 26 phút 16 tới lúc node bị xoá.

Hai giả định vẫn đứng nguyên vì lần chạy này không thử chúng: Spot có capacity khi cần node — lần này có, một lần là
một lần; và provider embedding hoạt động khi pod khởi động, điều mà ở real mode là thật vì pod mới embed một câu hỏi
thử lúc nạp index, nên nếu Hugging Face hỏng thì pod mới không bao giờ `Ready` và scale out đứng lại trong khi service
vẫn chạy tiếp trên những gì nó đang có. Lần chạy này ở fake mode nên không đi qua đường đó."

*Nếu được hỏi thêm:* tôi không tách riêng được thời gian chờ Spot. Cái đo được là **40 giây** từ lúc có pod
`Pending` tới lúc node thứ ba `Ready`, và **60 giây** tới lúc pod thật sự chạy trên nó — 20 giây chênh lệch đó là
taint khởi tạo, không phải Spot.

### A9. Giới hạn và nhìn lại

**A9.1** **Ý chính:** "Trần bốn node — vượt quá thì pod Pending. Scale out node mất vài phút, nên tải tăng đột
ngột sẽ vượt nó; chỉ khoảng trống dưới ngưỡng của pod mới đỡ được khoảng đó. Tín hiệu là một gauge lấy mẫu định
kỳ: một đợt tăng nằm gọn giữa hai lần scrape là vô hình với autoscaler. Mất một phần series không bị bắt. Và UI
không được autoscale."

*Nếu được hỏi thêm:* middleware tăng gauge trước khi handler chờ thread, nên gauge đếm cả request đang xếp hàng;
request còn nằm trong hàng đợi của web server thì chưa được đếm. Gauge cũng đếm cả probe health và readiness.

**A9.2** **Ý chính:** "Karpenter thay Cluster Autoscaler — nó cấp node theo đúng hình dạng pod cần, nhanh hơn, và
chọn được nhiều loại instance Spot hơn. Design đã để nó là P1. Sau đó là đặt giới hạn đồng thời một cách tường
minh, để ngưỡng của trigger gắn vào một cấu hình của chính mình chứ không phải một mặc định của thư viện."

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)

---

### A10. Câu đào sâu — Spot bị thu hồi

**A10.1** **Ý chính:** "Ba lớp, và tôi nói ngay: cả ba là *cấu hình*, chưa lớp nào được một lần thu hồi thật kiểm
chứng — trong hai ngày 22–23/09 không có lần thu hồi nào. Managed node group xử lý **thông báo chấm dứt**: rebalance
và drain trước khi máy mất; drain là eviction, nên trên đúng đường đó PodDisruptionBudget `minAvailable: 1` mới có
tác dụng. Nếu máy mất **không** báo trước thì PDB không giúp gì — thu hồi là involuntary, không đi qua Eviction API,
và tôi ghi đúng câu đó trong chart. Thứ sống sót qua một lần thu hồi đột ngột là `topologySpreadConstraints`: mỗi
node một replica *khi xếp được*, `maxSkew: 1` nhưng `whenUnsatisfiable: ScheduleAnyway`, nên **thường** mất một node
là mất một replica chứ không mất cả hai — 'thường', không phải 'chắc chắn', và evidence không ghi hai replica ấy nằm
ở đâu.

*Nếu được hỏi thêm:* thứ thật sự chưa được thử là chính lần thu hồi. Trong suốt lần chạy 22–23/09 không có lần thu
hồi Spot nào, nên ba lớp trên là *cấu hình* — tôi đọc được chúng trong chart và trong thiết kế, tôi không có một dòng
log nào nói chúng đã hoạt động. Cái tôi đo được là một sự việc gần đó và nó dạy đúng bài học: node thứ ba **tồn tại,
đã `Ready`, mà vẫn không nhận được pod** vì còn taint khởi tạo. Tồn tại không đồng nghĩa với nhận việc được — và một
lần thu hồi Spot sẽ trả lời câu hỏi ngược lại: mất việc có đồng nghĩa với mất khả năng phục vụ không.

Nếu phải dựng drill cho nó, tôi dùng đúng cách đã dùng cho mọi drill khác: `aws ec2 terminate-instances` một node
trong lúc k6 đang chạy ở mức tải nhẹ, rồi đo hai con số — số request lỗi, và thời gian tới khi đủ replica lại. Ở
scale-in tôi đã làm y hệt vậy và nó cho 4935 request với 0 lỗi; lý do phải có traffic là một scale-in đo trong im
lặng thì không có ai để mà làm mất.

**Mẹo:** phân biệt rõ ba lớp *cấu hình* với một lần *đo*. Người phỏng vấn hỏi câu này để xem bạn có gọi cấu hình là
bằng chứng hay không.
