# Đáp án tổng quan về project

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `SLO A5.2` trỏ tới bộ của stage tương ứng.

Phần app **đã làm và đã đo, chạy local** — nói bằng kinh nghiệm được. Bên dưới nó, tính tới **2026-09-23**: hạ tầng,
GitOps và CI/CD **đã dựng và đã đo trên AWS** (criteria #1, #3, #4, #5, #6, xem [`docs/evidence/`](../evidence/)) — cũng
nói bằng kinh nghiệm; canary, SLO, autoscaler và tracing **mới thiết kế** — nói bằng "tôi thiết kế", "tôi chọn". Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật; ghi chú **[kiểm chứng]** là
hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **phase app** cho phần đã làm; **stage** cho tám giai đoạn hạ tầng; **tiêu chí**
cho mười sáu điều kiện hoàn thành trong design; **pass sai** cho một phép kiểm xanh trong khi thứ nó canh đang hỏng.

**Số liệu đã có** — đo local ngày 2026-09-15 ([`../evidence/local.md`](../evidence/local.md)), được phép nói:

| Số | Giá trị | Dùng ở |
|---|---|---|
| Image cũ so với hai image mới | 6.45 GB → api 619 MB, ui 559 MB; cộng lại 1.18 GB, giảm khoảng 82% | A1.2, A2.1 |
| Index | 269 anime, embed trong 8.5 giây lúc build image | A2.1 |
| Negative test của index | `EXPECTED_DOCS=270` → build thất bại | A2.1 |
| Token Hugging Face trong image | 0 lần trong `docker history` và `docker save` | A2.1 |
| Hai request `/recommend` thật, qua Gemini | 3.0 s và 2.7 s đầu cuối; ước tính 0.0025 USD cho cả hai theo giá niêm yết tier trả phí | A2.1 |
| Fault drill 20% | đúng 80 request 200 và 20 request 503, ba counter khớp nhau | A2.1, A4.4 |
| Test | 17 test pass, ruff sạch, container chạy UID 10001 | A2.1 |

**Còn phải điền:**

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| Chi phí một phiên làm việc | Cost Explorer sau phiên đầu | A6.3 |
| Tiêu chí đầu tiên của hạ tầng được đóng, và con số của nó | Lần dựng đầu | A6.1, A7.3 |

---

## Phần A — Phỏng vấn

### A1. Giới thiệu

**A1.1** **Ý chính:** "Anime Recommender là một app RAG gợi ý anime — workload thì nhỏ, còn chủ đề là vận hành nó như một
đội SRE: SLO với alert theo burn rate, canary tự rollback, autoscaling theo đúng tín hiệu, và một LLM mà tôi thấy được chi
phí. Phần app tôi đã làm và đo, chạy local. Trên EKS tôi đã dựng tới stage 4: cụm, cây GitOps và pipeline CI/CD đang
chạy, năm tiêu chí đã đóng bằng số đo thật — trong đó có mức trễ mục tiêu T = 8 giây, lấy từ 230 request thật. Bốn stage
còn lại — canary, SLO, autoscaling, tracing — tôi đã thiết kế trọn vẹn nhưng chưa dựng. Nó là bản managed song song với
Medical, project mà tôi đã tự dựng Kubernetes bằng kubeadm."

**Mẹo:** ba thì phải nằm trong mười giây đầu — **đã đo ở local**, **đã dựng và đo trên AWS**, **đã thiết kế nhưng chưa
dựng**. Mọi câu hỏi sau đó sẽ dựa trên nó, nên nói sai thì ở đây là hỏng cả buổi.

**A1.2** **Ý chính:** "App tách thành hai: một API FastAPI giữ index vector 269 anime và gọi Gemini, và một UI
Streamlit mỏng. Phase app sửa sáu lỗi thật và đo kết quả: một image 6.45 GB thành hai image cộng lại 1.18 GB,
token không lọt vào layer nào, và tôi cố tình làm phép kiểm index thất bại để chắc nó bắt được lỗi.

Rồi tôi thiết kế tám stage hạ tầng, mỗi stage giải quyết thứ stage trước để lại — thứ tự ở A3.4. Ba cơ chế SRE là
phần lõi. Một: SLO availability 99.5% trên 28 ngày, alert khi burn rate vượt 13.44 lần trên cặp cửa sổ một giờ và
năm phút. Hai: canary 10, 50, 100 phần trăm, mỗi mức phải có tỉ lệ thành công ít nhất 99% và p95 không quá 1.2
lần bản stable. Ba: KEDA scale api từ 2 tới 8 pod theo số request đang xử lý, với ngưỡng lấy từ phép đo.

Xuyên suốt, mỗi stage có một mục riêng: nó có thể pass mà vẫn hỏng theo cách nào. Tất cả mới là thiết kế; con số đầu tiên của
hạ tầng sẽ là số resource của Terraform, ghi trước rồi mới so."

*Nếu được hỏi thêm:* thứ tự ở A3.4, pass sai ở A4.2.

**A1.3** **Ý chính:** "Một app gợi ý: người dùng mô tả thứ họ thích, API tìm các anime gần nhất trong index
vector rồi nhờ model viết lời gợi ý. Nó hợp cho bài tập SRE vì nó có đủ những thứ làm vận hành khó: phụ thuộc vào
hai API bên ngoài có giới hạn tốc độ, latency hàng giây, chi phí theo token, và thời gian gần như chỉ là chờ —
nên CPU không nói lên tải. Nhưng nó đủ nhỏ để một người chạy được, và có một fake provider để drill mà không tốn
tiền."

**A1.4** **Ý chính:** "Vì một project không dạy tốt được cả hai thứ: vận hành cụm, và vận hành service trên cụm.
Medical trả lời 'bạn có vận hành được Kubernetes không' — kubeadm, etcd, chứng chỉ, chuỗi cung ứng. Anime nhận
cụm như một thứ có sẵn và trả lời 'bạn có vận hành được một service trên nó không'. Hai câu hỏi khác nhau, với
bằng chứng khác nhau. Và vì dùng chung tài khoản AWS, zone và workstation với Medical, EKS là lựa chọn tự nhiên
cho vế managed."

*Nếu được hỏi thêm:* bộ so sánh riêng ở AWS A1.1; câu nào chỉ một bên trả lời được, và câu nào cả hai đều không,
ở AWS A1.4–A1.6 và [what each project proves](../aws/what-each-project-proves.md).

### A2. Trạng thái thật

**A2.1** **Ý chính:** "Đã làm và đo, chạy local: app tách API và UI, một image 6.45 GB thành hai image 619 và 559
MB — cộng lại 1.18 GB, giảm khoảng 82%. Index 269 anime embed trong 8.5 giây lúc build, và build thất bại nếu đặt
số mong đợi là 270. Token Hugging Face không xuất hiện lần nào trong history hay trong image xuất ra. Hai request
`/recommend` thật, qua Gemini, mất 3.0 và 2.7 giây tính cả embedding, ước tính khoảng 0.0025 USD cho cả hai. Một
fault drill 20% cho đúng 80 request 200 và 20 request 503, ba counter khớp nhau. 17 test pass, container chạy UID
10001. Trên AWS, tính tới 2026-09-23: hạ tầng, GitOps và CI/CD đã dựng và chạy — năm tiêu chí đã có số, trong đó
T = 8 giây từ 230 request thật. Còn lại canary, SLO, autoscaling và tracing thì mới thiết kế."

*Nếu được hỏi thêm:* phase app còn nợ vài việc tôi đã ghi rõ: lỗi Hugging Face lúc query đang thành 500 chưa phân
loại, ba endpoint health và metrics phải thành async, bucket histogram phải mịn hơn — cả ba làm trước stage Load.
Ghi prompt vào trace thì chưa viết.

**Mẹo:** "cộng lại giảm khoảng 82%" — không nói "giảm 90%". 90% chỉ là của api, so một image với một nửa thứ thay nó.

**A2.2** **Ý chính:** "Sáu lỗi, mỗi cái là thật. Một process Streamlit duy nhất, không có API — không có mã trạng
thái để đếm, nên không đo được SLI, không viết được load test. Index bị gitignore rồi `COPY` vào, nên một lần
build sạch ship một index *rỗng* mà không ai kêu. Một mẫu latency bằng không lúc khởi động làm số đếm của
histogram lệch số request mãi mãi. Một dependency không dùng kéo PyTorch vào image. Bucket latency cao nhất 10
giây, trong khi lời gọi LLM có thể vượt mức đó — timeout của nó là 30 giây — nên p95 mù đúng lúc cần nhất. Và
không có endpoint health, probe gọi `/` — pass cả khi index thiếu."

*Nếu được hỏi thêm:* lỗi index rỗng là ví dụ tốt nhất: bây giờ index được build trong lúc build image, và số tài
liệu được kiểm. CI/CD A3.2 kể chuyện làm phép kiểm đó thất bại bằng con số 270.

**A2.3** **Ý chính:** "Lần `docker compose up` đầu tiên không bind được cổng 8000, vì một stack khác đang giữ nó.
Container api bị bỏ lại không có mạng, và việc nạp index — vốn chỉ chạy một lần, không thử lại — hỏng vĩnh viễn.
Tôi không restart cho xong. Nguyên nhân ban đầu là môi trường, nhưng việc một lỗi tạm thời thành hỏng vĩnh viễn
là lỗi thiết kế. Giờ việc nạp chạy nền với backoff từ 1 tới tối đa 30 giây, `/readyz` báo lỗi gần nhất trong lúc
thử lại, còn `/healthz` vẫn 200 để startup probe của orchestrator quyết định khi nào bỏ cuộc. Có test riêng cho
nó."

**Mẹo:** câu "tôi không restart cho xong" cho thấy cách làm: tìm nguyên nhân gốc trước.

**A2.4** **Ý chính:** "Vì các stage phụ thuộc nhau chặt hơn vẻ ngoài. T đo ở stage Load quyết định SLO; con số
capacity quyết định ngưỡng của KEDA; bucket của histogram quyết định cả T lẫn độ nhạy của gate canary. Viết trọn
trước thì những phụ thuộc đó lộ ra trên giấy, nơi sửa rẻ. Và việc rà lại thiết kế đã tìm ra những lỗi mà nếu dựng
rồi mới thấy thì đắt hơn nhiều — A7.1."

### A3. Kiến trúc

**A3.1** **Ý chính:** "Ngoài cùng là hai cửa. Một ALB public cho app qua HTTPS, một ALB nội bộ cho bốn UI quản
trị, chỉ tới được qua WireGuard; cả hai dùng một chứng chỉ ACM. API của Kubernetes không có địa chỉ public nào —
tôi vào nó bằng tunnel SSM từ ops workstation. Bên trong là EKS với node group Spot từ hai tới bốn node. Argo CD
kéo mọi thứ từ Git theo wave. Prometheus với rule SLO do Sloth sinh sẵn trong CI và commit vào Git, Alertmanager
gửi tới Discord. Argo Rollouts; KEDA và Cluster Autoscaler; OpenTelemetry Collector tới Tempo và Langfuse.
Terraform giữ phần AWS, chia ba stack theo vòng đời."

*Nếu được hỏi thêm:* Terraform A1.1, GitOps A1.1.

**A3.2** **Ý chính:** "Người dùng vào UI trên `anime`, và UI gọi API. Với một client gọi thẳng API — như k6 —
request tới ALB public trên `api.anime`, TLS kết thúc ở đó, và listener chia request giữa target group stable và
canary theo trọng số. Pod api — đăng ký bằng IP — embed câu hỏi qua Hugging Face, tìm trong index, gọi Gemini,
trả lời; cả hai lời gọi ra ngoài đều đi qua NAT. Trên đường đi, histogram ghi latency cho SLI và gate, gauge ghi
số request đang xử lý cho KEDA, và span đi tới collector."

*Nếu được hỏi thêm:* UI gọi API qua ALB hay qua Service trong cụm là một điểm design còn mở. Nó quyết định
traffic của người dùng thật có đi theo trọng số canary hay không; drill thì không bị ảnh hưởng, vì k6 gọi thẳng
`api.anime`.

**A3.3** **Ý chính:** "Merge vào `main`. GitHub Actions lint, test, build index và kiểm số tài liệu, build hai
image, scan, rồi — chỉ trên `main` — đổi token OIDC lấy quyền push, push theo digest, ký keyless, gắn SBOM, và
commit một dòng digest mới vào Git. Argo CD thấy commit và cập nhật Rollout. Rollout cho bản mới 10%, chờ hai
phút, phân tích; 50%, chờ, phân tích; rồi 100%. Bản tệ hơn thì tự abort; quá ít traffic để phán xét thì dừng chờ
người. Chỉ API là Rollout — UI vẫn là Deployment."

*Nếu được hỏi thêm:* CI/CD A1.1, Delivery A1.1.

**A3.4** **Ý chính:** "Terraform, GitOps, CI/CD, Load, Delivery, SLO, Scaling, Tracing. Thứ tự là thứ tự phụ
thuộc. Không có cụm thì không có gì. Không có controller và secret thì không có cửa. Không có pipeline thì không
có bản mới để canary. Load đứng trước SLO vì T là một phép đo, không phải lựa chọn. Rollout đứng trước drill
alert vì drill được định nghĩa là một Rollout mang tỉ lệ lỗi. Scaling cần con số capacity của Load. Tracing đứng
cuối vì không gì phụ thuộc vào nó."

### A4. Những ý xuyên suốt

**A4.1** **Ý chính:** "Mỗi con số đã đo đều có bản ghi phép đo trong thư mục evidence, và mọi thứ chưa dựng nói
rõ là chưa dựng. Trong các bộ câu hỏi, số chưa đo là chỗ trống có tên, không phải một ước đoán. Và mỗi con số
mang theo điều kiện của nó — chế độ, cửa sổ, số mẫu — vì một con số không có điều kiện thì không so được với gì."

**A4.2** **Ý chính:** "Là một phép kiểm xanh trong khi thứ nó canh đang hỏng. Ở phase CI của Medical tôi đã gặp
năm phép kiểm như vậy trong cùng một phase — ví dụ một phép kiểm readiness lọc theo loại condition chứ không theo
trạng thái, nên pod đang khởi động vẫn được tính là Ready. Từ đó, mỗi stage của Anime có một mục riêng liệt kê
những cách nó có thể pass mà vẫn hỏng, và mỗi tiêu chí có một cột pass sai. Mỗi stage hoá ra có một dạng riêng: ở
GitOps là quan sát thứ mà chính lỗi cũng tạo ra; ở Load là con số đúng về thứ khác; ở Delivery là quyết định trên
con số không phải của canary; ở Tracing là giá trị có mặt mà không có nghĩa."

*Nếu được hỏi thêm:* GitOps A7.4, CI/CD A8.2, Load A6.3, Delivery A9.1, SLO A8.2, Scaling A8.2, Tracing A8.3.

**Mẹo:** kể được dạng pass sai của từng stage là cách chứng minh bạn nắm cả hệ thống, không chỉ từng mảnh.

**A4.3** **Ý chính:** "Ở gần như mọi stage. Query Prometheus trên dữ liệu không tồn tại trả về rỗng, và rỗng khác
không. Alert trên dữ liệu rỗng không bao giờ bắn. Phân tích canary gặp rỗng thì báo lỗi và abort mọi release.
KEDA mặc định coi rỗng là không và scale về tối thiểu giữa lúc tải cao. Token mặc định bằng không thì chi phí là
một ngày rẻ không có thật. Lần nào cách sửa cũng là nói rõ rỗng nghĩa là gì — lỗi, dừng, hay giữ nguyên — thay vì
để nó thành không."

*Nếu được hỏi thêm:* Load A2.2, Delivery A4.3, Scaling A6.1, Tracing A6.3.

**A4.4** **Ý chính:** "Một chế độ của api không gọi model, cũng không gọi Hugging Face, với latency và tỉ lệ lỗi
đặt được. Nhờ nó, load test, canary drill và alert drill chạy ở tốc độ cao, lặp lại chính xác, và không tốn tiền
— fault drill 20% local cho đúng 80 và 20. Nguy hiểm ở hai chỗ. Con số của nó không so được với con số thật, nên
mọi con số ghi kèm chế độ. Và tỉ lệ lỗi chỉ fake provider đọc — đặt lên một bản chạy model thật thì không tiêm
gì, và drill ghi nhận một thành công giả."

*Nếu được hỏi thêm:* fake provider còn được định giá như model thật, nên chi phí phải lọc theo model — Tracing A6.2.

**A4.5** **Ý chính:** "Vì chi phí — một người, một tài khoản, không lý do gì để cụm chạy qua đêm. Nó ép bốn điều.
Thứ phải sống qua đêm nằm ở một stack Terraform riêng. Bằng chứng phải được lưu trong phiên, vì metric và trace
chết theo cụm. Mọi alert có cửa sổ dài hơn dữ liệu đang có đều phải được xem là chưa hiệu chỉnh. Và SLO 28 ngày
chỉ là một định nghĩa, không bao giờ là thứ tôi tuyên bố đã đạt."

*Nếu được hỏi thêm:* Terraform A2.1, SLO A2.4 và A5.2.

### A5. Rủi ro và đánh đổi

**A5.1** **Ý chính:** "Rủi ro có thể chặn ngay từ đầu: tài khoản dùng chung với Medical đang ở gói Free, và gói đó chỉ
chạy các loại instance free-tier-eligible. Nên tôi kiểm nó đầu tiên: EKS có trong gói, Spot chạy được, nhưng cả bốn
loại tôi định dùng đều không eligible — nên node group chỉ còn `m7i-flex.large`. Sau đó: giới hạn tier miễn phí của
Gemini và Hugging Face làm méo phép đo — nên chỉ baseline chạy model thật, còn lại chạy fake và ghi rõ chế độ. Spot
hết capacity — chỉ còn một loại instance, nên rủi ro này lớn hơn; phương án là cùng loại đó chạy on-demand. Và cấu
hình chia traffic ở ALB có thể mất nhiều thời gian hơn dự kiến — phương án là canary theo tỉ lệ replica, yếu hơn, và
bằng chứng sẽ nói vậy."

*Nếu được hỏi thêm:* kết quả kiểm gói (2026-09-22): gói FREE, còn 91.64 USD credit dùng chung với Medical; EKS
gọi được; `t3.large`, `t3a.large`, `m5.large`, `m6i.large` không eligible; một `m7i-flex.large` Spot chạy thật được
rồi xoá. Dry-run thì chấp nhận cả loại không eligible, nên nó không chứng minh được gì ở đây
(`docs/evidence/account.md`). Thêm một rủi ro nhỏ hơn: ACM có gia hạn một
chứng chỉ không gắn vào đâu phần lớn thời gian hay không — Terraform A8.4.

**A5.2** **Ý chính:** "Cắt theo thứ tự: phần P1, rồi KEDA và Cluster Autoscaler — giữ số replica cố định lấy từ
capacity đo được, và nói rõ — rồi drill alert nhưng giữ rule, rồi export Langfuse nhưng giữ Tempo. Không bao giờ
cắt: rule SLO, phân tích canary và rollback, và các con số k6. Ba thứ đó không thay được bằng một dòng 'nói rõ';
autoscaling thì thay được bằng một số replica cố định lấy từ con số đo được."

**A5.3** **Ý chính:** "Một NAT gateway cho cả hai zone — tiết kiệm giờ NAT thứ hai, đổi lại mất zone đó là mất
mọi thứ pod gọi ra ngoài, kể cả webhook Discord, và SLI ghi sự cố đó như lỗi của chính service. Controller load
balancer — nó gánh cả truy cập lẫn release. Gateway WireGuard — mất nó là mất mọi UI quản trị và `kubectl`, nhưng
service vẫn chạy, vì truy cập của người vận hành không nằm trên đường đi của request. Và ba thứ của Medical: zone
Route 53 — vì một domain thứ hai tốn tiền hằng năm — ops workstation và bucket state. Mỗi cái được ghi ra kèm lý
do chấp nhận, thay vì để ai đó tự phát hiện."

*Nếu được hỏi thêm:* không có dead-man's switch cho đường báo động — SLO A7.3.

### A6. Câu hỏi hay gặp khác

**A6.1** **Ý chính:** "Trước cả tiêu chí đầu tiên: gói của tài khoản có cho EKS, Spot và loại instance tôi chọn
không. Rồi tiêu chí #1 — số resource dự kiến ghi ra *trước*, apply, plan lại và không có thay đổi. Và trước khi
tin bất kỳ con số nào từ Prometheus: target của api phải up và có dữ liệu trên counter tổng."

*Nếu được hỏi thêm:* Terraform A7.2, Load A2.1. Kết quả `[điền: tiêu chí đầu tiên được đóng và con số của nó]`.

**A6.2** **Ý chính:** "Chắc chắn rằng con số mà một quyết định đọc là con số về đúng thứ đang được quyết — số của
canary chứ không phải của stable, ngưỡng đang có hiệu lực chứ không phải ngưỡng viết trên giấy, cặp cửa sổ đã
hiệu chỉnh chứ không phải cặp tính từ vài giờ dữ liệu. Mỗi cái đều có một cách hỏng im lặng."

*Nếu được hỏi thêm:* Delivery A4.1 và A5.1, SLO A5.2.

**A6.3** **Ý chính:** "Chi phí chính là phí control plane của EKS, NAT, hai ALB và node Spot, chỉ trong những giờ
cụm chạy. Tôi giữ nó bằng bốn thứ: cụm bị huỷ mỗi tối, Spot thay cho on-demand, một NAT thay vì hai, và budget
cảnh báo ở 50 và 100 USD. Model thật chạy trên tier miễn phí; mọi drill dùng fake provider. Chi phí thật của một
phiên thì phải đo."

*Nếu được hỏi thêm:* chi phí một phiên `[điền: từ Cost Explorer]`. Phí giờ của control plane **[kiểm chứng: mức hiện tại]**.

**A6.4** **Ý chính:** "Đã có trong thiết kế: không có access key AWS nào — CI dùng OIDC, mỗi controller có Pod
Identity riêng, External Secrets chỉ đọc đúng ba secret có tên. API của Kubernetes không có địa chỉ public. UI
quản trị chỉ qua VPN. Image được scan và ký, token build không lọt vào layer nào. Còn thiếu, và đã ghi ra: không
có admission control nào kiểm chữ ký; Prometheus và Alertmanager không có đăng nhập; và khi bật ghi prompt, nội
dung người dùng gõ sẽ đi tới Langfuse, một bên thứ ba."

*Nếu được hỏi thêm:* Terraform A5.1, CI/CD A4.6, GitOps A8.1, Tracing A5.2.

**A6.5** **Ý chính:** "Một ô nhập trên trang Streamlit. Họ mô tả thứ họ thích, và nhận lại một đoạn gợi ý kèm
danh sách các anime đã được truy xuất. Dưới câu trả lời có trace id — nếu ai đó phàn nàn về một câu trả lời, tôi
tìm được đúng request đó."

**A6.6** **Ý chính:** "Ở hai mức. Với chất lượng tìm kiếm, có một eval gate — hai mươi câu hỏi với tiêu đề mong
đợi, tính `hit@4`, chặn pull request nếu điểm tụt dưới baseline. Nó là P1, nên là thứ bị cắt đầu tiên. Với chất
lượng câu viết của model thì hiện chưa có gì tự động; đó là lý do việc ghi prompt và câu trả lời vào Langfuse
quan trọng — để đọc được."

*Nếu được hỏi thêm:* CI/CD A7.2 và A7.3, Tracing A5.1.

### A7. Nhìn lại

**A7.1** **Ý chính:** "Câu chuyện tôi thích kể nhất: tôi từng nghĩ drill alert chỉ cần một giờ traffic sạch. Tính
lại, thì với một giờ sạch, cặp 6h/30m chưa hiệu chỉnh sẽ vượt ngưỡng trước cặp 1h/5m, vì cửa sổ sáu giờ chỉ chứa
đúng giờ sạch đó cộng phần lỗi — theo tính toán, với giả định Sloth gộp hai cặp bằng `or` **[kiểm chứng]**. Nên
drill giờ chạy khoảng ba giờ sạch và ghi burn của từng cửa sổ. Những lỗi khác cũng tìm ra khi rà lại: endpoint
public với danh sách IP được thay bằng đóng hẳn; External Secrets suýt được đọc `anime/*`, tức đọc được cả key
VPN; và Argo Rollouts không có điều kiện riêng cho inconclusive, nên chặn kết quả rỗng phải viết vào cả hai điều
kiện **[kiểm chứng]**."

*Nếu được hỏi thêm:* health check cho Application thì là bài học mang từ Medical: bản đầu của Medical chỉ đọc
Healthy và thả hết các wave cùng lúc, tốn một lượt cấp Let's Encrypt; Anime dùng bản đòi cả Synced ngay từ
bootstrap. Terraform A9.1, GitOps A9.1, Delivery A6.3, SLO A5.2.

**Mẹo:** kể một lỗi cụ thể, nói nó được tìm ra thế nào và sửa ra sao. Người phỏng vấn nhớ câu chuyện, không nhớ danh sách.

**A7.2** **Ý chính:** "Kiểm gói của tài khoản và hạn mức của các tier miễn phí trước khi viết một dòng thiết kế
nào dựa vào chúng. Viết bucket của histogram cho đúng từ đầu, vì chúng quyết định cả T lẫn độ nhạy của canary. Và
cho project một domain và bucket state riêng ngay từ đầu, để không có ràng buộc chéo nào với Medical."

*Nếu được hỏi thêm:* với một đội thay vì một người — Terraform A9.2, GitOps A9.2.

**A7.3** **Ý chính:** "Rằng tôi coi bằng chứng quan trọng hơn dấu xanh. Tôi viết ra trước một phép kiểm có thể
sai theo những cách nào, tôi nói rõ thứ gì đã đo và thứ gì chưa, và khi gặp lỗi thì tìm nguyên nhân gốc trước khi
sửa. Tôi cũng chấp nhận ghi 'chưa được thử' hơn là ép ra một đồ thị đẹp."

*Nếu được hỏi thêm:* khi hạ tầng bắt đầu được dựng, con số đầu tiên sẽ là `[điền: tiêu chí đầu tiên được đóng và
con số của nó]`.

---

[Câu hỏi](questions.md) · [README gốc](../../README.md) · [Design](../eks-sre-llmops-design.md)
