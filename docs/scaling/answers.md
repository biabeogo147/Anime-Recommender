# Đáp án Scaling

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Load A4.5` trỏ tới bộ tương ứng.

Stage này **mới thiết kế, chưa chạy**. Mọi câu ở thì hiện tại bên dưới nói về thiết kế, và câu đầu tiên của A1.1
nói rõ điều đó một lần. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **in-flight** cho số request đang được xử lý; **trigger** cho điều kiện KEDA
đọc; **điểm gãy** cho chỗ p95 tách khỏi p95 lúc tải thấp, đo ở stage Load; **scale out / scale in** cho thêm / bớt.

**Số liệu đã có:** chưa có số nào cho stage này. Con số `4` trong design chỉ là giá trị tạm, không phải ngưỡng.

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| In-flight mỗi pod tại điểm gãy, và ngưỡng trigger đặt dưới nó | Lần ramp ở stage Load | A2.2 |
| CPU và memory mỗi pod tại điểm gãy, thành resource request | Lần ramp ở stage Load | A4.3 |
| Replica và node theo thời gian, giá trị trigger, độ trễ scale out của pod và của node, lúc quay về mức tối thiểu | Lần chạy scaling | A1.3, A5.1, A5.2 |
| Tám pod ở mức request đã đo có vừa trên hai node không | Lần chạy scaling | A4.3 |
| Thời gian chờ Spot khi cần node | Lần chạy scaling | A8.3 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi mới thiết kế, chưa chạy. KEDA scale Rollout của api từ 2 tới 8 pod, theo số request
đang xử lý trung bình mỗi pod, với ngưỡng đặt thấp hơn điểm gãy đo ở stage Load. Cluster Autoscaler thêm node, từ 2 tới 4,
khi có pod không còn chỗ chạy. Cả hai là vòng điều khiển có độ trễ, cả hai đọc những tín hiệu có thể biến mất. Và mỗi cái có
thể trông như đã chạy đúng trong khi cái kia thì không."

*Nếu được hỏi thêm:* KEDA scale được Rollout vì Rollout có subresource `/scale`, giống Deployment. UI không được autoscale.
Tín hiệu ở A2.1, khi tín hiệu biến mất ở A6.1, pod và node ở A4.1.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "thiết kế, chưa chạy", rồi trình bày tự nhiên.

**A1.2** **Ý chính:** "Request xếp hàng, latency tăng, và error budget bắt đầu bị đốt. Không có gì thêm capacity: số pod là
con số cố định ghi trong Git, bất kể traffic."

**A1.3** **Ý chính:** "Chạy lại lần ramp với ScaledObject và Cluster Autoscaler đang hoạt động: replica tăng dần
về 8, node về 4, rồi cả hai quay về. Bằng chứng là replica và node theo thời gian, giá trị của trigger, độ trễ
scale out của pod và của node tách riêng, thời điểm scale in của pod so với cửa sổ của HPA, và thời điểm bớt node
so với hai mốc mười phút của Cluster Autoscaler."

*Nếu được hỏi thêm:* kết quả `[điền: replica và node theo thời gian, giá trị trigger, các độ trễ]`.

### A2. Tín hiệu và ngưỡng

**A2.1** **Ý chính:** "Vì request ở đây gần như chỉ chờ — chờ API embedding, chờ model. Một pod bận có CPU rảnh và một hàng
đợi phía sau. HPA theo CPU sẽ ngồi ở vài phần trăm trong khi request chồng chất, không bao giờ scale, và dashboard còn bảo
service đang được dùng ít. Số request đang xử lý mới là thứ tăng đúng lúc service đuối."

**A2.2** **Ý chính:** "Từ lần ramp ở stage Load: tại điểm gãy, lần chạy đó sẽ đọc thẳng từ gauge xem mỗi pod đang
giữ bao nhiêu request. Trigger được đặt thấp hơn con số đó một khoảng. Định luật Little — số request đang xử lý
bằng tốc độ đến nhân thời gian trung bình — là phép đối chiếu, để chắc con số đọc được khớp với tốc độ và latency
đo cùng lúc."

*Nếu được hỏi thêm:* dùng latency *trung bình*, không phải p95 — p95 thổi phồng số request một pod giữ. Và ở mép
một ramp đang tăng, hệ thống không hẳn ổn định, nên phép đối chiếu chỉ gần đúng; gauge mới là số đọc chính. Kết
quả `[điền: in-flight tại điểm gãy và ngưỡng trigger]`.

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
này. EKS tự gắn tag cho Auto Scaling group của managed node group, nên Cluster Autoscaler tự tìm ra nó. Bốn loại
instance Spot cùng cỡ, và điều đó quan trọng, vì Cluster Autoscaler giả lập node mới từ một khuôn duy nhất
**[kiểm chứng]**.

**A4.2** **Ý chính:** "Chủ yếu là resource *request*, không phải mức dùng thật. Scheduler đặt pod theo thứ pod
xin, và Cluster Autoscaler thêm bớt node cũng theo đúng thước đo đó. Một pod xin ít thì vừa gần như mọi chỗ."

*Nếu được hỏi thêm:* ngoài request còn các ràng buộc xếp lịch — rải pod theo topology, hay giới hạn số pod mỗi node theo số
địa chỉ IP mà VPC CNI cấp được — cũng làm pod Pending **[kiểm chứng]**.

**A4.3** **Ý chính:** "Thì node không bao giờ cần thêm, và nửa node của #14 không xảy ra. Tôi sẽ không tăng
request để thấy nó xảy ra — như thế là tạo ra một đồ thị đẹp về một con số không ai đo. Request được đặt từ mức
một pod thật sự dùng tại điểm gãy. Nếu nó vừa, nửa node được ghi là *chưa được thử*, kèm lý do."

*Nếu được hỏi thêm:* kết quả `[điền: CPU và memory tại điểm gãy]` và `[điền: tám pod có vừa hai node không]`.

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
rút nhiều pod cùng lúc. Thời điểm quay về `[điền: thời điểm quay về mức tối thiểu]`.

**A5.2** **Ý chính:** "Theo một đồng hồ riêng của Cluster Autoscaler: nó chỉ bỏ một node sau khi node đó không
cần tới trong mười phút, và không trong mười phút sau một lần scale out — hai mốc đó bằng mặc định của Cluster
Autoscaler, nhưng được ghi tường minh trong cấu hình, vì #14 đo theo chúng. Node đang giữ pod có storage cục bộ có thể bị bỏ qua, trừ khi pod nói nó
được phép bị dời. `/tmp` của api là một `emptyDir`, nên pod api mang annotation cho phép dời, với giá trị là tên
volume."

*Nếu được hỏi thêm:* nên câu "hệ thống đã về mức tối thiểu" có hai câu trả lời, theo hai đồng hồ, và lần chạy
scaling báo cả hai. Không chỉ pod api: pod nào có `emptyDir` — Prometheus, repo-server của Argo CD — cũng có thể
chặn việc bớt node, và cờ mặc định cho việc đó đã đổi qua các phiên bản **[kiểm chứng]**. PodDisruptionBudget của
api khiến Cluster Autoscaler đuổi từng pod một. Lúc node quay về `[điền: thời điểm node quay về 2]`.

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

**A8.3** **Ý chính:** "Khi chạy xong, stage này sẽ chứng minh: dưới tải tăng, api tự thêm replica theo tín hiệu
của chính nó và quay về mức tối thiểu sau đó; và nếu request cho phép, node được thêm và bớt — mỗi độ trễ được
ghi lại, hoặc nửa node được ghi là chưa được thử. Nó giả định Spot có capacity khi cần node, và provider
embedding hoạt động khi pod khởi động. Một trong hai hỏng thì scale out đứng lại, còn service chạy tiếp trên
những gì nó đang có."

*Nếu được hỏi thêm:* thời gian chờ Spot `[điền: thời gian chờ Spot khi cần node]`.

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
