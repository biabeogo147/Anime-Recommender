# Năm dòng CV, mở từng dòng

Người phỏng vấn đọc CV và hỏi theo **từng dòng**. Bộ đề thì xếp theo stage. Trang này là đường đi từ "dòng thứ ba"
sang "các câu sẽ bị hỏi".

Mỗi dòng: câu CV nguyên văn → nói lại bằng lời thường → khái niệm nén trong đó → số liệu kèm nguồn → câu hỏi, bấm để
xem đáp án mẫu. Chế độ đo của mọi con số ở [`modes.md`](modes.md).

Nguồn: `latex-CV/sections/projects/film-recommender.tex`, `evidence/cv.md` (bảng 17 dòng có cột **Mode**),
`evidence/guide-measurements.md` (M1–M8, mỗi phép đo có `Valid only if`).

---

## Dòng 1 — Cluster and access

> **Cluster and access.** Terraform splits the infrastructure into three stacks so the EKS stack can be destroyed
> when idle and rebuilt from code. The Kubernetes API is private, reached through an SSM tunnel; admin interfaces
> are available only over WireGuard.

**Nói bằng lời thường.** Hạ tầng chia ba stack Terraform theo **thời gian sống**, không theo chức năng. `shared` giữ
thứ phải sống qua mỗi lần xoá — ECR, secret, vai OIDC của CI, chứng chỉ ACM. `cluster` giữ VPC, EKS, node group,
gateway WireGuard, và bị huỷ khi không dùng. `bootstrap` chỉ cài Argo CD và app gốc. Câu hỏi quyết định một resource
thuộc bên nào là: "`make down` có được phép chạm vào nó không?".

API server không có **địa chỉ** public. Tôi vào bằng port-forward SSM tới gateway WireGuard, rồi `kubectl` gọi
`127.0.0.1:6443`. Bốn UI quản trị nằm sau một ALB internal, chỉ mở khi VPN bật.

**Khái niệm trong câu này.**

| Khái niệm | Đủ mức nói ra miệng |
|---|---|
| **Chia theo vòng đời** | `destroy` luôn xoá trọn một state file, nên state chung là vòng đời chung. Để ECR cùng stack với cluster thì mỗi sáng phải chạy lại CI và chứng chỉ bị cấp mới thay vì gia hạn. |
| **Chiều đọc giữa hai stack** | `cluster` đọc output của `shared` qua data source và **không bao giờ ghi vào**. Nhờ chiều đó, lệnh huỷ chỉ với tới được đúng thứ nó được phép huỷ. |
| **Private-only endpoint** | EKS **vẫn cấp một tên DNS public**, nhưng với `endpointPublicAccess=false` tên đó chỉ resolve ra `10.30.250.10` và `.21`. Cái không tồn tại là *địa chỉ*, không phải *cái tên*. |
| **SSM port forwarding** | Session Manager mở cổng qua agent trên EC2 — không bastion mở cổng 22, không SSH key. |
| **EKS Pod Identity** | **Sáu** association gắn ServiceAccount với IAM role: ALB controller, External Secrets, **EBS CSI**, Cluster Autoscaler, external-dns, Argo Rollouts. Là Pod Identity, *không* phải IRSA. |
| **ACM** | AWS cấp và tự gia hạn chứng chỉ, gắn vào ALB bằng annotation. Cluster không giữ private key nào cho hai tên public. |

**Số liệu.**

| Đọc được | Giá trị | Nguồn |
|---|---|---|
| `shared` / `cluster` / `bootstrap`: plan (ghi trước) = applied = trong state | 15 / 92 / 2 — tổng 109 | `terraform.md:12,15` |
| Thời gian apply từ trống | 0m55s · 12m18s · 1m14s | `terraform.md` |
| Plan lại, **không** dùng `-refresh=false` | `No changes.` cả ba | `terraform.md` |
| Gọi thẳng endpoint từ ngoài | `curl: (28) Connection timed out after 10002 ms` | `terraform.md:30,34` |
| Cụm | EKS 1.36, platform `eks.14`, public endpoint `False`, 2 node Spot `m7i-flex.large` | `terraform.md` |
| Số chủ thể gọi vào AWS, không cái nào dùng key | **6** | `1-terraform/README.md`, "Decision 4" |

**Sẽ bị hỏi gì.**

<details>
<summary>Sao không để endpoint public rồi giới hạn bằng allowlist IP?</summary>

Allowlist là một danh sách có người phải bảo trì, và nó sai ngay lần đầu có ai làm việc từ mạng khác. Với endpoint
private thì không có danh sách nào. Nói cho chính xác về *cái* mà private mua được: ở trong VPC chỉ cho bạn một kết
nối TCP — API server vẫn đòi một danh tính EKS và RBAC. **Mạng là lớp ngoài, không phải phân quyền.**

Và tôi kiểm nửa phủ định chứ không chỉ đọc cấu hình: gọi thẳng từ ngoài thì timeout.

> "An allowlist is a list somebody maintains, and it is wrong the first time someone works from a different network.
> To be precise about what private buys: being inside the VPC gets you a TCP connection and nothing more — the API
> server still requires an EKS identity and RBAC. The network is the outer layer, not the authorization. And I
> checked the negative half: calling the endpoint from outside times out."

</details>

<details>
<summary>"Apply từ trống rồi plan không thay đổi" chứng minh gì, và điểm yếu ở đâu?</summary>

Nó chứng minh cấu hình khớp thực tế và không có drift — và vì tôi **ghi số resource ra trước khi apply** nên đó là
một khẳng định, không phải một con số chép lại sau. Plan lại cũng không dùng `-refresh=false`, nên resource lệch khỏi
cấu hình sẽ hiện thành thay đổi.

Điểm yếu tôi nói trước: lần đó resolve provider theo khoảng `~> 6.0` và **Git chưa có lock file**, nên nó được đo với
đúng phiên bản `terraform init` lấy hôm ấy — `aws` ra 6.66.0. Lock file commit ngày hôm sau, nên từ đó trở đi một lần
dựng lại mới so được với nó. Tôi chưa dựng lại từ lúc ấy, nên đó là tính chất của **code**, chưa phải một phép đo.

> "It proves the configuration matches reality and nothing drifted — and because I wrote the expected count down
> first, the number is an assertion rather than a recording. The weakness is that the run resolved providers against
> a range with no lock file in Git. The locks landed the next day, so from here on a rebuild would pin the same
> versions — but I have not rebuilt since, so that is a property of the code, not a measurement."

</details>

<details>
<summary>Một gateway gánh hai việc — có phải điểm gãy duy nhất?</summary>

Với **đường quản trị** thì đúng, và tôi biết mất nó thì mất gì: không UI nội bộ, không `make tunnel`, nên không
`kubectl` — tôi thành mù. Cái nó **không** làm mất là service: người dùng đi qua ALB public, và Argo CD chạy *trong*
cụm nên vẫn tiếp tục hoà giải. Hệ thống tự chữa trong lúc tôi không thấy gì.

Sự bất đối xứng đó là có chủ ý: không thứ gì thuộc đường truy cập của người vận hành nằm trên đường request. Nếu có
người dùng thật, tôi sẽ đặt máy đích của tunnel vào một autoscaling group cỡ một, trải hai subnet, để địa chỉ được
*lấy lại* chứ không phải *học lại*.

> "For the admin path, yes, and I know what losing it costs: no internal UIs and no tunnel, so no kubectl — I would
> be blind. What it does not cost is the service: users reach the public load balancer, and Argo CD keeps
> reconciling from inside the cluster. That asymmetry was deliberate — nothing about operator access sits in the
> request path."

</details>

---

## Dòng 2 — Canary releases

> **Canary releases.** Argo Rollouts shifts 10%, then 50%, then 100% of traffic. Prometheus measures the canary's
> success rate and compares its latency with the stable version. In a rollback test, a canary configured to fail 20%
> of its requests was aborted automatically at the 10% stage after 167 s; 1.36% of all requests failed while it was
> live.

**Nói bằng lời thường.** Deployment của api đổi thành một `Rollout`. Mỗi bản mới nhận 10% traffic, dừng cho một
`AnalysisRun` truy vấn Prometheus bốn lần, rồi lên 50%, dừng nữa, rồi 100%. **Ba** cổng mỗi bước: số request canary
nhận được (≥ 20, để không phán xử trên traffic rỗng), tỉ lệ thành công (≥ 0.99), và tỉ số p95 canary so với stable
(≤ 1.2).

Điểm quan trọng nhất là truy vấn lọc theo `rollouts-pod-template-hash` của **chính ReplicaSet canary**. Lọc theo
trung bình toàn service thì 10% traffic xấu bị 90% tốt pha loãng và cổng không bao giờ đỏ.

**Khái niệm trong câu này.**

| Khái niệm | Đủ mức nói ra miệng |
|---|---|
| **AnalysisRun** | Loạt truy vấn Prometheus phán xử một bước canary; đủ lần thất bại thì Rollout tự abort và trả traffic về stable. |
| **canary-hash và stable-hash** | Hai ReplicaSet của cùng một Rollout. Hai hash **bằng nhau** là false pass: cổng đang so bản cũ với chính nó. |
| **`latency-ratio`, không phải "p95 ≤ T"** | T là số real mode, drill chạy fake mode — cổng tuyệt đối không thể đỏ ở đây. So hai bản cạnh nhau thì chế độ bị loại khỏi câu hỏi. |
| **`failureLimit` = 1** | Một phép đo trượt chưa đủ, phải hai lần — nên một phần của 167 giây là chờ phép đo thứ hai. |
| **`Inconclusive`** | Kết quả rỗng không khớp cổng nào, nên rollout **dừng chờ người** thay vì abort. Xem câu về Spot dưới. |

**Số liệu.**

| Đọc được | Giá trị | Nguồn |
|---|---|---|
| Drill promote: start → `Healthy` | **8 m 23 s** | `delivery.md` |
| AnalysisRun của bản tốt | **2, cả hai `Successful`** | `delivery.md` |
| `canary-hash` / `stable-hash` | `586cd55b4f` / `589794b4fd` — **khác nhau** | `delivery.md:18` |
| Drill rollback: start → abort | **167 s** | `delivery.md:100` |
| `success-rate` của bản xấu | **0.813 · 0.819** (cổng 0.99) | `delivery.md` |
| `latency-ratio` của bản xấu | **1.042 · 1.030 — đạt cổng cả hai lần** | `delivery.md` |
| Canary nhận / canary lỗi | 250.9 / **45.0** — 17.9% traffic của chính nó, so với 20% cấu hình | `delivery.md` |
| Lỗi trên **toàn bộ** request lúc canary còn sống | **1.36%** (≈45 trên ≈3300) | `delivery.md:105` |

**Sẽ bị hỏi gì.**

<details>
<summary>Chi tiết nào trong drill này mạnh nhất?</summary>

Rằng **bản xấu không hề chậm**. `latency-ratio` đo 1.042 và 1.030 và *đạt* cổng ở cả hai lần probe. Chỉ
`success-rate` bắt được nó. Một quy trình release phán xử theo độ trễ thôi đã promote bản này lên 100%. Hai cổng
trượt vì hai lý do khác nhau ở đây không phải dư thừa — mỗi cổng mù đúng cái mà cổng kia thấy.

> "The bad version was not slow. The latency gate passed it at both probes — 1.04 and 1.03 against a threshold of
> 1.2 — and only the success-rate gate caught it. A release judged on latency alone would have gone to a hundred per
> cent. The two gates are not redundancy; each is blind to what the other sees."

</details>

<details>
<summary>Lần drill đầu tiên xảy ra chuyện gì?</summary>

Nó **abort một bản hoàn toàn lành**. Điều kiện viết theo dạng Go `math.IsInf(f, sign)`, nhưng Argo Rollouts đánh giá
bằng expr-lang, ở đó `isInf` nhận một tham số — nên biểu thức **không compile được**. Một điều kiện không compile thì
không bao giờ làm metric trượt: mỗi lần đánh giá ra error, năm error vượt `consecutiveErrorLimit` 4, và Rollout
abort. Từ ngoài nhìn giống y hệt một bản release xấu — cùng `abort=true`, cùng `Degraded`, cùng quay về stable. Chỉ
dòng message phân biệt được, và nó giờ nằm trong bảng troubleshooting.

Nửa đáng an tâm là **chiều nó hỏng**: một cổng hỏng đã *chặn* một bản release, không phải cho qua. Tôi sửa qua pull
request chứ không sửa trên cluster, và canary của lần merge sau chứng minh bản sửa miễn phí.

> "My first drill aborted a completely healthy build. The condition used Go's `math.IsInf(f, sign)`, but Argo
> Rollouts evaluates with expr-lang where `isInf` takes one argument, so it never compiled. A condition that cannot
> compile can never fail the metric: every evaluation errored, five errors passed the limit, and the rollout
> aborted. From outside it was indistinguishable from a bad release. The reassuring half is the direction it failed
> in — a broken gate blocked a release instead of passing one."

</details>

<details>
<summary>Một node Spot bị thu hồi giữa lúc phân tích canary đang chạy. Cổng làm gì?</summary>

Nếu pod canary **cuối cùng** mất, mẫu của nó già ra khỏi cửa sổ hai phút và truy vấn trả về một **vector rỗng** — mà
phép so `< 20` không đánh giá được vector rỗng. Nếu để nguyên thì phép đo thành error, đủ error là run thất bại, và
cổng **abort bản release vì một sự kiện về capacity**.

Đó là chỗ tôi đã đóng sẵn: cả `successCondition` lẫn `failureCondition` đều mở đầu bằng `len(result) > 0`, nên kết
quả rỗng không khớp cái nào và phép đo thành `Inconclusive` — rollout dừng chờ người. Comment đầu file nói thẳng nó
tồn tại để "không quy lỗi cho bản release vì một sự kiện về capacity".

Cùng lập luận — **vắng dữ liệu không phải bằng không** — tôi áp ở cả hai chỗ: stage 7 là `ignoreNullValues=false` cho
KEDA, stage 5 là cặp guard này. Chỗ chưa trọn là **tài liệu**: bảng rủi ro §5 vẫn ghi trường hợp này như một lỗ hổng
kèm chữ "to be verified" — tài liệu cũ hơn code. Và tôi chưa *đo* nó: trong hai ngày chạy không có lần thu hồi nào.

> "If the last canary pod goes, its samples age out of the two-minute window and the query returns an empty vector,
> which the `< 20` comparison cannot evaluate — so left alone, the gate would abort a release because of a capacity
> event. That is closed: both conditions start with `len(result) > 0`, so an empty result matches neither and the
> measurement is Inconclusive, which pauses for a human. Same reasoning as `ignoreNullValues=false` on the KEDA
> side. What I have not done is measure it — there was no Spot reclaim during the run."

</details>

<details>
<summary>1.36% đó có đốt error budget không? Có gọi page không?</summary>

Có đốt, và đốt là có chủ ý. Nhưng nó không gọi page, và số học giải thích tại sao: 45 lỗi trong một cửa sổ 5 phút ở
20 req/s là khoảng 6000 request, tức tỉ lệ lỗi ~0.75%. So với budget 0.5% thì burn rate khoảng **1.5**, trong khi
page cần **13.44** ở cả cửa sổ 1 giờ và 5 phút.

Con số 1.5 đó là tôi **tính**, không phải đo — evidence không ghi lần drill canary nào gọi page, và tôi không suy ra
từ sự im lặng đó.

Ý nghĩa thiết kế: **canary được phép tiêu một ít budget có chủ ý, để một lần rollout đầy đủ không tiêu hết budget
một cách vô tình.** 1.36% trong 167 giây là cái giá đã biết trước của việc biết được bản này xấu.

> "It burns budget, deliberately. It did not page, and the arithmetic says why: forty-five errors in a five-minute
> window at twenty requests a second is about zero point seven five per cent, a burn rate around one point five
> against a page factor of thirteen point four four. That figure is my arithmetic, not a measurement. The design
> intent is that a canary spends a little budget on purpose so a full rollout does not spend all of it by accident."

</details>

---

## Dòng 3 — Capacity

> **Capacity.** k6 with a simulated model put the ceiling at 94 requests/s for two pods while CPU stayed low, so
> KEDA scales on concurrent requests, not CPU. At 267 requests/s it scaled from 2 to 8 pods and 2 to 3 nodes,
> holding p95 under 1.5 s across 224,396 requests with no failures; with two fixed pods, p95 had already reached
> 15.6 s at less than half that load.

**Nói bằng lời thường.** Trước khi bật autoscaling, tôi đo một "đơn vị" cố định: hai pod, không autoscaler, k6 gửi
theo **arrival rate** tăng dần tới 120 req/s. Tốc độ *phục vụ* dừng ở 93.9 req/s trong khi tốc độ *gửi* vẫn leo —
đó là trần. Và trần ấy khớp một con số tính được **trước** khi chạy: pool 40 luồng, fake mode mất trung bình 0.85 s
một request, nên 40 / 0.85 = 47 req/s mỗi pod, **94.1 cho hai**.

Ở đúng cái trần đó mỗi pod dùng **0.23 core**. Các luồng không làm việc — chúng ngủ chờ provider. Nên một autoscaler
theo CPU sẽ thấy service rảnh đúng lúc độ trễ tăng gấp mười. Vì vậy KEDA scale theo **in-flight mỗi pod**, ngưỡng 30.

**Khái niệm trong câu này.**

| Khái niệm | Đủ mức nói ra miệng |
|---|---|
| **Open model** | Gửi theo arrival rate định trước. Closed model thì virtual user chờ câu trả lời, nên service chậm làm nó gửi ít đi — *coordinated omission* — và điểm gãy trông dịu hơn thực tế. |
| **Knee, định nghĩa trước khi chạy** | Điểm đầu tiên p95 vượt **1.5 lần** trung bình bốn điểm p95 đầu. Viết và commit trước, để "chỗ graph bẻ" không bị chọn sau khi đã nhìn graph. |
| **in-flight** | Số request đang xử lý trong một pod. Một pod có 40 luồng, mỗi luồng giữ một request, nên in-flight trên 40 nghĩa là hàng đợi đang hình thành — một **định nghĩa**. |
| **HPA stabilisation window** | 300 giây trước lần giảm đầu: một quãng lặng ngắn không được làm co cluster sắp cần lại công suất. |
| **Taint khởi tạo** | Node mới tồn tại và `Ready` rồi vẫn có thể chưa nhận pod. Đó là lý do node tính bằng phút. |

**Số liệu.**

| Đọc được | Giá trị | Nguồn |
|---|---|---|
| **Trần phục vụ, 2 pod** | **93.9 req/s**, hai lần chạy độc lập | `load.md:57` |
| Giới hạn thread pool, tính trước khi chạy | **94.1 req/s** | `load.md` |
| CPU / RAM mỗi pod tại trần | 0.23 core / 143 MiB | `load.md:114` (mỗi lần chạy: `:59`) |
| Hai pod cố định ở đỉnh ramp 120 req/s | p95 **15.6 s** | `load.md` |
| Ngưỡng KEDA | **30** in-flight mỗi pod | `load.md` |
| Dự đoán trước khi chạy: 7 pod vừa 2 node, pod thứ 8 không | **đúng cả hai nửa** (31–31.9 ở 7 replica, 27.7–28.9 ở 8) | `scaling.md` |
| Node 3 `Ready` / đủ 8 pod chạy | +40 s / +60 s từ pod `Pending` | `scaling.md` |
| Ra 8 pod / về 2 pod | 6 m 35 s / 10 m 02 s | `scaling.md` |
| Toàn bộ ramp | **224396** request, **0** lỗi, p95 **1.44–1.47 s** | `scaling.md:70-75` |
| Scale-in dưới tải nhẹ 5 req/s | **4935** request, **0** lỗi | `scaling.md` |

**Sẽ bị hỏi gì.**

<details>
<summary>Anh load-test một model giả à? Thế đo được gì?</summary>

Đúng, và có chủ ý. Gọi provider thật thì 39000 request vừa tốn tiền vừa chạm rate limit, và con số ra sẽ mô tả quota
của provider chứ không mô tả cluster. Fake mode **không có cuộc gọi ra ngoài nào** — nó giữ nguyên thread pool, hàng
đợi, middleware, histogram, và bỏ đi mạng.

Ba nguồn độc lập nói con số này là thật: hai lần chạy ra cùng 93.9; một phép tính viết trước cho 94.1; và p95 phần
bằng phẳng đúng bằng p95 lý thuyết của hàm ngủ, 1.42 s tính được so với 1.43 và 1.45 s đo được. Cái tôi **không** làm
là đem p95 fake mode so với T — T là số real mode.

> "Yes, deliberately. Against a real provider those thirty-nine thousand requests would cost money and hit a rate
> limit, and the number would describe the provider's quota instead of the cluster. Fake mode makes no outbound call
> at all — same thread pool, same queue, no network. Three independent sources agree on the ceiling: two runs at
> 93.9, a thread-pool limit of 94.1 computed beforehand, and a flat-region p95 that matches the sleep's own p95."

</details>

<details>
<summary>Một service chỉ chờ I/O mạng thì vì sao lại bị chặn ở 40 luồng? Sao không async?</summary>

Handler `/recommend` **đã là** `async def`. Cái nằm trong thread pool là hàm recommender đồng bộ: handler gọi
`run_in_threadpool(...)`, và pool mặc định của Starlette có 40 luồng — nên kích thước pool *chính là* trần đồng thời
của một pod.

Việc dồn phần chặn vào pool là có chủ ý, và lý do nằm ở ba endpoint còn lại: `/healthz`, `/readyz`, `/metrics` đều
`async def`, có comment giải thích trong code — một handler `def` thường sẽ chạy trong *cùng* pool bị giới hạn ấy,
nên một api đang bão hoà sẽ ngừng trả lời chính probe của nó, và Kubernetes giết những pod chỉ đang bận.

Muốn nâng trần thì làm cuộc gọi provider async thật; lúc đó đồng thời bị chặn bởi socket và memory, cỡ hàng trăm
in-flight mỗi pod. **Tín hiệu autoscale không đổi**, chỉ ngưỡng cao hơn nhiều. Tôi cố ý không sửa app: mục đích là đo
một *platform* trên một app cố định, và sửa app giữa đường thì cái trần đã đo hai lần mất giá trị.

> "The handler is already `async def`. What sits in the thread pool is the synchronous recommender, dispatched with
> `run_in_threadpool`, and Starlette's default pool is forty threads — so the pool size *is* the per-pod concurrency
> ceiling. That is deliberate: the health and metrics endpoints are async on purpose, because a plain `def` handler
> would queue behind model calls and a saturated api would stop answering its own probes. Making the provider call
> natively async would trade a thread ceiling for a socket ceiling; the autoscaling signal would not change."

</details>

<details>
<summary>So 15.6 s ở 120 req/s với 1.47 s ở 267 req/s — công bằng không?</summary>

Không like-for-like, và tôi nói rõ chiều lệch: 120 req/s là **dưới một nửa** 267, nên phép so thiên về phía bảo thủ
— hai pod cố định ở 267 còn tệ hơn 15.6 s. Cái nó cho thấy không phải "cluster scale được" mà là **"tải gấp ba mà
không ai nhận ra"**. Hàng đợi không hình thành vì pod được thêm vào trước khi nó kịp hình thành.

> "Not like-for-like, and the direction is conservative: a hundred and twenty a second is less than half of two
> sixty-seven, so two fixed pods at the higher rate would have been worse than fifteen point six seconds. The claim
> is not that the cluster scaled — it is that the load tripled and nobody noticed."

</details>

<details>
<summary>Làm sao biết pod tăng vì autoscaler chứ không vì một lần deploy?</summary>

Bốn phép đọc, mỗi phép chặn một false pass. **Trigger động trước**: chuỗi trigger leo từ 0 lên 249 *trước khi*
desired replica rời khỏi 2 — desired tăng mà trigger không tăng thì đó là scale tay hoặc bug. KEDA đọc Prometheus
thành công suốt (`numberOfFailures: 0`), và `ignoreNullValues=false` làm truy vấn rỗng thành **lỗi** chứ không thành
0. Trần 8 là của `maxReplicas` và metric đã tụt dưới ngưỡng, không phải vì pod bị bỏ `Pending`. Và
`Rollout ["/spec/replicas"]` nằm trong `ignoreDifferences`, nên self-heal không giành lại số replica — thiếu nó thì
Git nói 2 và cả lần scale-out bị hoàn tác trong vài giây.

> "The trigger moved first — it rose from zero to two hundred and forty-nine before desired replicas left two.
> KEDA read Prometheus successfully throughout, and `ignoreNullValues=false` makes an empty query an error rather
> than a zero. And Argo CD's `ignoreDifferences` on the replica field is what stops self-heal undoing the scale-out
> within seconds."

</details>

<details>
<summary>Node của anh là Spot. Một lần thu hồi thì sao?</summary>

Ba lớp, và tôi nói ngay: **cả ba là cấu hình, chưa lớp nào được một lần thu hồi thật kiểm chứng** — trong hai ngày
chạy không có lần thu hồi nào.

Managed node group xử lý **thông báo chấm dứt**: rebalance và drain trước khi máy mất; drain là eviction, nên trên
đúng đường đó PodDisruptionBudget `minAvailable: 1` mới có tác dụng. Nếu máy mất **không** báo trước thì PDB không
giúp gì — thu hồi là involuntary, không đi qua Eviction API, và tôi ghi đúng câu đó trong chart. Thứ sống sót qua một
lần thu hồi đột ngột là `topologySpreadConstraints`: mỗi node một replica *khi xếp được*, `maxSkew: 1` nhưng
`whenUnsatisfiable: ScheduleAnyway` — nên **thường** mất một node là mất một replica, không phải chắc chắn.

Muốn đo thì tôi dùng đúng cách đã dùng cho mọi drill khác: terminate một node trong lúc k6 chạy tải nhẹ, rồi đo số
request lỗi và thời gian tới khi đủ replica lại — y như scale-in đã cho 4935 request với 0 lỗi.

> "Three layers, and all three are configuration: there was no reclaim during the run. The node group handles the
> termination notice with a rebalance and a drain, and a drain is an eviction, so that is the path where the
> disruption budget applies. If the machine goes without notice the budget does nothing — a reclaim is involuntary
> and never touches the Eviction API. What survives that is the topology spread, and it is best-effort:
> `ScheduleAnyway`, so usually one replica is lost, not certainly."

</details>

---

## Dòng 4 — SLOs and alerting

> **SLOs and alerting.** A 99.5% availability SLO and an 8 s latency target rounded up from a server-side p95 of
> 7.07 s over 230 real gpt-4o-mini requests, with burn-rate alerts on both. In a failure drill, a simulated model
> returned errors for 50% of requests; the alert reached Discord in 9.5 minutes, 8 of them the 1-hour burn-rate
> window filling.

**Nói bằng lời thường.** Hai SLO: availability 99.5% và latency với ngưỡng T. T **không** do tôi chọn — nó đo được:
230 request thật qua `gpt-4o-mini`, đọc p95 **phía server**, ra 7.07 s nội suy, và T là mép bucket ngay trên đó,
**8 s**, vì SLI đọc counter ở `le=T` nên T buộc phải là một mép bucket có thật.

Cảnh báo dùng **burn rate nhiều cửa sổ**: page là phép OR của hai cặp — 1h/5m hệ số 13.44 và 6h/30m hệ số 5.6, trên
chu kỳ 28 ngày. Sloth sinh các rule đó, chạy trong container; CI chạy `make slo-check` và fail nếu file trong Git lệch
bản sinh lại, và rule đang commit chính là bản CI sinh ra. Nên thứ Prometheus nạp luôn là thứ nằm trong Git, và
không có Sloth operator nào.

**Khái niệm trong câu này.**

| Khái niệm | Đủ mức nói ra miệng |
|---|---|
| **Error budget và burn rate** | SLO 99.5% cho phép 0.5% request lỗi trong 28 ngày. Burn rate là tốc độ tiêu budget so với tốc độ "vừa đủ hết đúng lúc hết chu kỳ"; 13.44 là hết trong khoảng hai ngày. |
| **Vì sao hai cửa sổ một cặp** | Cửa sổ dài chống báo động giả, cửa sổ ngắn làm alert tắt nhanh khi sự cố hết. Phải **cả hai** cùng vượt mới nổ. |
| **Vì sao 13.44 chứ không 14.4** | 14.4 / 6 / 3 / 1 là bộ cho chu kỳ 30 ngày. Cùng tỉ lệ budget trên 28 ngày cho 13.44 / 5.6 / 2.8 / 0.93. |
| **T phải là mép bucket** | SLI đếm request nhanh hơn T bằng counter tại `le=T`. Không có bucket 7.07 s, nên T là 8 s. |
| **Vì sao đọc p95 phía server** | k6 đo thêm mạng và TLS trên mọi request, mãi mãi. Hai số vẫn khớp: 6.28 s là order statistic của k6, 7.07 s là nội suy qua bucket rộng 2 giây. |

**Số liệu.**

| Đọc được | Giá trị | Nguồn |
|---|---|---|
| T, và số request đo được | **8 s** trên **230** request, 0 lỗi | `load.md:14-17` |
| p95 server nội suy / p95 k6 | 7.07 s / 6.28 s | `load.md` |
| Prometheus **đánh giá** rule | 6 group, **34** rule, **0** lần đánh giá lỗi | `slo.md` |
| Giờ sạch trước khi tiêm lỗi | **71997** request, **0** lỗi, store 9.67 giờ tuổi | `slo.md` |
| Chia phần | +45 s scrape · +15 s recording rule · **+8 m 00 s** số học cửa sổ | `slo.md:34-38` |
| Alert `firing` / tin vào Discord | 9 m 00 s / **9 m 30 s** (biên dưới, khoảng 9:30–9:36) | `slo.md:40` |
| Error ratio lúc bắn | **0.497** | `slo.md` |
| Cặp bắn: 5m / 1h so với 13.44 | 99.43 / 14.66 — vượt cả hai | `slo.md` |
| Cặp không bắn: 6h so với 5.6 | **5.30** — thiếu | `slo.md` |
| Alert tự tắt sau khi sửa | **26 m 06 s** | `slo.md` |

**Sẽ bị hỏi gì.**

<details>
<summary>9 phút rưỡi mới gọi được người — có chậm quá không?</summary>

Chỉ phút đầu là độ trễ hệ thống: 45 giây scrape cộng 15 giây recording rule. **Tám phút ở giữa là số học cửa sổ**, và
đó là điểm của thiết kế chứ không phải độ trễ cần tối ưu đi. Cửa sổ 1 giờ phải tích đủ tỉ lệ lỗi để vượt hệ số 13.44;
muốn nổ nhanh hơn thì phải làm cửa sổ ngắn hơn, và đổi lại là nhiều báo động giả hơn.

Con số đúng là "tới lúc một **người** được gọi", không phải "tới lúc Prometheus nổi alert" — nên tôi lấy 9 m 30 s chứ
không lấy 9 m 00 s. Và nó là **biên dưới**, vì hai lý do cùng chiều: Discord chỉ hiện đến phút, và `alert.fault` được
ghi *sau* vòng poll Healthy nên lỗi có thể tới traffic sớm hơn vài giây.

> "Only the first minute is system latency — forty-five seconds of scrape and fifteen of recording rules. The eight
> minutes in the middle are the window arithmetic, and that is the design rather than a delay to tune away: a
> shorter window pages faster and pages on noise. I quote the time until a person is reached, and it is a lower
> bound — Discord timestamps to the minute, and my fault marker is written after the health poll."

</details>

<details>
<summary>Vậy SLO 99.5% đã đạt chưa?</summary>

Chưa, và sẽ không bao giờ nói là đã đạt trên hệ này. "SLO định nghĩa ở 99.5% trong 28 ngày" đúng từ ngày commit;
"đã duy trì 99.5% trong 28 ngày" thì không, và không bao giờ đúng trên một cluster bị huỷ khi không dùng. Cái tôi đo
được là **đường dẫn alert hoạt động**: budget cháy thật, các cặp cửa sổ vượt hệ số thật, và một người thật nhận được
tin trong 9 phút rưỡi.

> "No. The SLO is defined at ninety-nine point five over twenty-eight days, which is true the day it is committed —
> but 'sustained' would never be true on a cluster torn down when idle. What I measured is that the alerting path
> works end to end."

</details>

<details>
<summary>Guide dự đoán 4 phút, thực tế 9. Sai ở đâu?</summary>

Guide trông chờ cặp **6h/30m** bắn trước vì hệ số thấp hơn (5.6). Nhưng cặp đó *không thể* thắng trên một store đã
giữ hàng giờ traffic sạch: cửa sổ 6 giờ có mẫu số lớn đến mức một lỗi 50% cần khoảng hai mươi phút mới đẩy nó qua
5.6 — đo được 5.30. Cặp bắn là **1h/5m**.

Điều đó làm con số *mạnh hơn*: 1h/5m là cặp đã được hiệu chuẩn, cái có cửa sổ một giờ chứa đúng một giờ sạch (store
9.67 giờ tuổi). Nên 9 phút rưỡi là thời gian cắt ngưỡng của cặp hiệu chuẩn, không phải sản phẩm của một cửa sổ thiếu
dữ liệu. Guide đã sửa, với 5.30 ghi lại làm lý do.

Cái *thật* chưa hiệu chuẩn trên nền tảng này là hai cặp ticket 1d/2h và 3d/6h — cửa sổ dài hơn tuổi của store.

> "The guide expected the six-hour pair, which has the lower factor. That pair cannot win on a store already holding
> hours of clean traffic — its denominator needs about twenty minutes to cross. The one-hour pair fired instead, and
> that makes the figure stronger: it is the calibrated pair, the one whose window held a full clean hour. What is
> genuinely uncalibrated here are the two slow-burn ticket pairs, whose windows are longer than the store's age."

</details>

<details>
<summary>Sao alert lâu tắt hơn lúc bắn — 26 phút so với 9?</summary>

Vì lúc sửa xong thì cặp 1h/5m đã tự sai — `rate5m` rỗng đi trong năm phút. Cái giữ page lại là cặp **6h/30m**, cặp
đã trở thành đúng *trong lúc* có lỗi. Page tắt khi cửa sổ 30 phút đẩy đủ phần lỗi ra ngoài để tụt dưới 5.6.

Đây là tính chất nội tại của burn-rate alerting, không phải cấu hình sai: đúng những cửa sổ dài giúp một lỗi lẻ không
gọi ai cũng là cửa sổ giữ page lại sau khi bản sửa đã lên. Cần biết **trước** chứ đừng biết trong lúc sự cố — một
người vận hành chờ page tắt cùng lúc với bản sửa sẽ kết luận bản sửa không ăn và đi tìm một sự cố thứ hai không tồn
tại. Đó cũng là dòng runbook giờ đã ghi.

Và tôi kiểm nó tắt *thật* chứ không phải tắt vì hết traffic: page cũng tắt khi mẫu số biến mất, và trên Discord hai
thứ đó giống nhau. Traffic là 40 req/s ở cả hai mốc.

> "By the time the fix landed the one-hour pair was already false — the five-minute rate empties in five minutes.
> What held the page up was the six-hour pair, which had become true during the fault. That asymmetry is inherent:
> the long windows that stop a stray error from paging anyone also stop the page clearing the moment a fix lands. An
> operator who does not know that goes looking for a second fault. I also checked it cleared because the errors
> aged out, not because traffic stopped — throughput was the same at both marks."

</details>

<details>
<summary>Có alert nào bắn mà không phải do anh tiêm lỗi không?</summary>

Có, và nó đúng. Alert **ticket** của SLO latency tự bắn mấy giờ trước drill: ramp của stage 4 đã đẩy p95 lên 15.6 s
so với T = 8 s, và những request đó còn nằm trong cửa sổ 6h và 3d. Nó tự tắt lúc 09:33Z, **khoảng một phút trước**
mốc ramp ra khỏi cửa sổ 6 giờ (09:34:26Z) — cửa sổ `rate` đã loãng đủ trước khi mẫu cuối rơi ra.

Hai điều rút ra. **SLI không có nhãn chế độ** — nó chỉ lọc `route="/recommend"` — nên traffic do chính load test của
tôi sinh ra đốt cùng error budget với traffic của người dùng. Đó đúng là chuyện xảy ra trong production khi ai đó
chạy load test lên một service đang sống. Cách sửa là một nhãn: tách traffic tổng hợp ra, hoặc cho nó SLI riêng. Tôi
để nguyên vì ticket bắn trên load test của tôi **là** hành vi trung thực.

Và **alert tự tắt khi nguyên nhân hết**; không ai ack hay silence gì. Một hệ mà alert phải tắt bằng tay sẽ dạy người
vận hành tắt alert bằng tay, rồi họ tắt đúng cái quan trọng.

> "Yes — the latency ticket fired on its own hours before the drill, because the stage-four ramp had driven p95 to
> fifteen point six seconds and those requests were still inside the six-hour window. The SLI carries no mode label,
> so my own load test burns the same budget a user would. The fix is a label; I left it because a ticket firing on
> my own load test is the honest behaviour."

</details>

<details>
<summary>Làm sao biết rule đã thật sự được nạp?</summary>

Đây là false pass nguy hiểm nhất của tiêu chí này: một `PrometheusRule` mà monitoring stack không chọn thì **được
nhận và bị bỏ qua**, và một drill chạy vào đó im lặng hoàn toàn mà không có lỗi ở đâu cả. Nên tôi kiểm rằng Prometheus
**đánh giá** chúng: 6 rule group, 34 rule, 0 lần đánh giá thất bại. Ngoài ra kiểm route Alertmanager tồn tại, secret
webhook đọc được (kiểm độ dài, không in ra), và quan trọng nhất — **gửi thử một alert không liên quan tới rule nào**,
một `AnimeDeliveryTest` tiêm tay, để thấy đường tới Discord tự nó hoạt động.

> "A PrometheusRule the monitoring stack does not select is accepted and silently ignored, so a drill against it
> produces no page and no error anywhere. I check that Prometheus *evaluates* them — six groups, thirty-four rules,
> zero evaluation failures — and I prove delivery separately with an injected alert that involves no rule at all."

</details>

---

## Dòng 5 — Tracing and cost

> **Tracing and cost.** OpenTelemetry sends traces to Tempo, and a Grafana latency chart links to the trace behind
> each point. Only real-model traces reach Langfuse: none of 6,343 drill requests did. Token counts and published
> prices put gpt-4o-mini at $0.42 per 1,000 requests.

**Nói bằng lời thường.** Api **đẩy** span qua OTLP tới một OpenTelemetry Collector, và collector tách một luồng
thành hai đích: **Tempo** nhận mọi span, trong cluster; **Langfuse** chỉ nhận span của LLM, và chỉ khi provider là
model thật. Tempo trả lời "trong request này đã xảy ra gì"; Langfuse trả lời "model làm gì và tốn bao nhiêu".

Trên dashboard, panel p95 mang theo **exemplar** — một điểm trên biểu đồ mở ra đúng trace đằng sau nó.

Chi phí không đọc từ hoá đơn: token do api tự đếm và ghi vào metric, nhân bảng giá công bố, ra **$0.4186 cho 1000
request**. Giá kèm ngày đọc, vì đó là một trang web có thể đổi mà không thông báo.

**Khái niệm trong câu này.**

| Khái niệm | Đủ mức nói ra miệng |
|---|---|
| **OTLP và fan-out** | Một luồng span vào, hai pipeline ra, mỗi pipeline có filter riêng. Nhờ tách vậy mà lần hỏng đầu đọc được: Tempo giữ trace đầy đủ trong khi Langfuse trống. |
| **Exemplar** | Trace id gắn kèm một mẫu histogram, để biểu đồ số liệu nối được sang trace cụ thể. |
| **Connector spanmetrics** | Biến span thành metric cho Prometheus — nguồn của con số 6076 span, và là cách chứng minh trace *có tồn tại*. |
| **`GENERATION` observation** | Kiểu span của Langfuse cho một lượt gọi model, mang model, token vào/ra và chi phí. |
| **Vì sao chi phí phải kèm ngày giá** | Giá không có trong API nào; nó nằm trên một trang không hiển thị ngày sửa. Không kèm ngày thì con số không tái lập được. |

**Số liệu.**

| Đọc được | Giá trị | Nguồn |
|---|---|---|
| Token một request thật, trong Tempo | **957** vào + **461** ra | `tracing.md:28` |
| Cùng trace đó trong Langfuse | **1418** token (= 957 + 461), $0.00042, 7 observation | `tracing.md` |
| Request fake mode: Tempo / Langfuse | có (`anime.llm.provider = fake`) / **0** observation | `tracing.md` |
| Một trace thật **tạo sau** trace fake | 7 observation | `tracing.md` |
| Drill 5 phút: request / span / trace rò | **6343** / **6076** / **0** | `tracing.md:47-49` |
| Chi phí mỗi 1000 request | **$0.4186** | `tracing.md:66` |
| Đối chiếu: $0.01739 trên 40 request | $0.435 mỗi 1000 | `tracing.md` |
| Giá dùng, và **ngày đọc** | $0.15 / $0.60 mỗi 1M — **22/09/2026** | `tracing.md:69-70` |

**Sẽ bị hỏi gì.**

<details>
<summary>Chứng minh filter hoạt động thế nào? "0" cũng là cái một export hỏng tạo ra.</summary>

Đúng, nên tôi **không đo sự vắng mặt**. Tôi đo một thứ đáng ra phải xuất hiện *trước*: lấy một trace thật được tạo
**sau** trace fake, và đợi tới khi nó hiện trong Langfuse. Khi nó đã hiện, ingestion đã vượt qua mốc thời gian đó —
nên việc trace fake không có là một **câu trả lời**, không phải một sự chậm trễ.

Và số liệu đi ba chiều: 6343 request trong cửa sổ drill, **6076 span qua connector spanmetrics** — nên trace có tồn
tại thật và có tới Tempo — và **0** trace riêng biệt trong Langfuse. Không phải "ít". Không cái nào.

Quy tắc tôi rút ra: *đừng đo sự vắng mặt, hãy đo một thứ mà nếu đường ống còn sống thì nó buộc phải xuất hiện trước.*

> "Zero on its own has two readings — the filter blocked it, or ingestion has not caught up. So I don't measure the
> absence: I fetch a real trace created *after* the fake one and wait until it is visible. Once it is, ingestion has
> passed that point in time, and the fake trace's absence is an answer rather than a delay. Three figures back it:
> six thousand three hundred requests, six thousand spans through the connector, zero distinct Langfuse traces."

</details>

<details>
<summary>$0.42 là hoá đơn thật à?</summary>

Không. Token là đo được — api đọc usage provider trả về và ghi vào metric — còn giá là bảng giá công bố, đọc ngày
22/09/2026. Tôi đối chiếu ba đường tính độc lập: tỉ số trên cửa sổ `increase()` mười phút ra $0.4186; tổng $0.01739
chia 40 request ra $0.435 mỗi nghìn; và Langfuse tự tính $0.00042 cho một request bằng bảng giá riêng của nó. Ba phép
tính khác nhau, ba bảng giá khác nhau, cùng đáp số tới hai chữ số có nghĩa.

> "No — the tokens are measured, the prices are the published list read on a stated date. Three independent routes
> agree to two significant figures: the ten-minute ratio, the run total divided by its request count, and Langfuse's
> own price table for a single request."

</details>

<details>
<summary>False pass của con số chi phí là gì?</summary>

Một số `0` đầy tự tin: model không có trong `config/pricing.yaml`, hoặc có với giá 0, thì dashboard vẽ một đường
phẳng sạch sẽ ở mức không — và panel vẫn render bình thường. Nên phép kiểm không phải "panel có hiện" mà là "giá trị
lớn hơn 0 và dòng giá phía sau nó tồn tại".

Bẫy ngược lại tinh hơn, và nó là chỗ sắc nhất của cả vốn từ này: `pricing.yaml` có một entry `fake:` **đặt giá y hệt
một model thật**, và metric fake mode mang nhãn `model="fake"`. Một lần chạy fake mode vì thế sinh ra một con số đô
la trông rất thật, từ token bịa — không phân biệt được bằng mắt. **Luôn phải đọc nhãn `model`.**

> "A confident zero — a model missing from the price file, or priced at zero, draws a clean flat line and the panel
> renders perfectly. And the reverse is sharper: fake mode is priced like a real model and its metrics are labelled
> `model=fake`, so a fake run produces a realistic dollar figure out of fabricated tokens. Always read the model
> label."

</details>

---

## Sáu sự cố để kể

Cả sáu đều tạo ra một câu trả lời **sai nhưng hợp lý** chứ không tạo ra lỗi. Đó là hình dạng của mọi lần hỏng đáng
viết xuống, và là thứ người phỏng vấn muốn nghe nhất.

<details>
<summary>1 · Hai trạng thái giống nhau từ bên ngoài: cổng từ chối bản xấu, và cổng tự hỏng</summary>

**Triệu chứng:** `abort=true`, `Degraded`, traffic về stable — giống y hệt một bản release xấu.

**Nguyên nhân:** điều kiện viết theo dạng Go `math.IsInf(f, sign)`, nhưng expr-lang có `isInf` một tham số. Không
compile ⇒ mỗi lần đánh giá ra error ⇒ 5 error vượt `consecutiveErrorLimit` 4 ⇒ abort. Canary lúc đó hoàn toàn khoẻ:
`success-rate` đo 1 và 1.

**Bài học:** chỉ dòng message phân biệt được hai trạng thái. Và **chiều nó hỏng là chiều đúng**: một cổng hỏng đã
chặn một bản release, không phải cho qua. Sửa qua pull request, không sửa trên cluster — đúng tính chất mà stage
GitOps tồn tại để thiết lập.

> "A rollout aborted and went Degraded, which from the outside is exactly what a bad release looks like. The
> canary was healthy — success rate measured 1. My latency condition was written in Go's two-argument form,
> `math.IsInf(f, sign)`, but expr-lang takes one argument, so the expression failed to compile and every
> evaluation returned an error. Five errors passed the consecutive-error limit of four and the analysis aborted.
> Two things I take from it: only the message line tells a broken gate from a rejected release, and the gate
> failed in the safe direction — it blocked a release rather than admitting one. I fixed it through a pull
> request, not on the cluster, because self-heal would have undone a manual fix anyway."

</details>

<details>
<summary>2 · Một đường export chỉ ghi thì không có phép kiểm</summary>

**Triệu chứng:** không có gì. Request vẫn trả 200, ứng dụng không báo gì.

**Nguyên nhân:** Langfuse Cloud giữ mỗi region trên host riêng, dữ liệu riêng, **key riêng** — nên một endpoint trỏ
sai region không báo lỗi, nó chỉ bị từ chối key và im lặng. `otlpEndpoint` trỏ EU trong khi project ở US.

**Bài học:** nó chỉ lộ ra vì lệnh **đọc** (`make langfuse-obs`) suy ra API host từ *cùng* dòng cấu hình đó, nên một
giá trị sai làm hỏng cả hai nửa và làm nửa im lặng phát ra tiếng. Mọi đường chỉ-ghi trong hệ này giờ phải có một lệnh
đọc dùng chung đúng dòng cấu hình đó.

> "Nothing was wrong from the application's side: requests returned 200 and no error was logged. My OTLP
> endpoint pointed at Langfuse's EU host while the project lived in US, and because each region is a separate
> deployment with its own keys, the export was rejected on authentication and dropped silently. A write-only
> export path has no test in it. It surfaced only because the command that *reads* observations derives its API
> host from the same config line, so one wrong value broke both halves and the loud half spoke for the quiet
> one. That is now the rule: every write-only path needs a read command that shares its configuration."

</details>

<details>
<summary>3 · Một API "không có dữ liệu" và một API "không trả dữ liệu ở endpoint này"</summary>

**Triệu chứng:** `/api/public/v2/observations` trả `model=- usage={}`.

**Nguyên nhân:** endpoint list trả một bản tóm tắt, trong đó `modelId` và các field giá là `null` **dù Langfuse đang
giữ** model, token và chi phí.

**Bài học:** tin cái list là đã viết *"OpenAI returned no usage"* vào file bằng chứng — một câu sai, và là một kết
quả có thật mà guide yêu cầu ghi lại trung thực, nên nó sẽ không bị ai chất vấn. Web UI nói ngược lại, và
`make langfuse-obs` giờ lấy từng generation theo id.

> "The observations list endpoint returned the model as a dash and usage as an empty object. The obvious
> reading is that the provider returned no token counts, and I nearly wrote that into my evidence file as a
> finding — which would have been a false statement that nobody would ever have questioned, because my own
> procedure asks me to record results honestly. The list endpoint returns a summary in which the model and
> pricing fields are null even though Langfuse holds them; the web UI showed the model, the tokens and the
> cost. The command now fetches each generation by id. The general lesson: an API that says *no data* and an
> API that says *not at this endpoint* look identical, and only a second source separates them."

</details>

<details>
<summary>4 · Spec đã đổi chế độ, traffic thì chưa</summary>

**Triệu chứng:** spec đã ghi `fake` mà chín request trong mười vẫn trả về `gpt-4o-mini`.

**Nguyên nhân:** Rollout dừng ở một canary không kết luận được, nên `stable` vẫn nằm ở bản real mode — 90% traffic đi
vào pod cũ. Guide chỉ biết nói "gửi lại request", thứ không giúp gì ở mức 10%.

**Bài học:** phép kiểm đúng là **`stable = latest`**, *không phải* `provider=fake`. Cái sau nói spec đã đổi, cái
trước nói traffic đã chuyển. Khối đổi chế độ giờ promote cho tới khi `Healthy` chứ không promote một lần.

> "I switched the service to fake mode, confirmed the spec said fake, and then nine requests in ten still came
> back from gpt-4o-mini. An earlier rollout had stopped at an inconclusive canary, so stable was still the
> real-mode revision and was taking ninety percent of the traffic. My procedure said *send the requests
> again*, which is useless when one in ten hits the new pod. The right check was `stable == latest`, not
> `provider == fake`: the spec tells you the intent changed, only the rollout state tells you the traffic did.
> The mode-switch step now promotes until the rollout is Healthy instead of promoting once."

</details>

<details>
<summary>5 · Cặp cửa sổ được trông đợi lại không thể thắng</summary>

**Triệu chứng:** guide dự đoán page trong ~4 phút; thực tế 9 phút.

**Nguyên nhân:** cặp 6h/30m có hệ số thấp hơn nên được trông đợi bắn trước, nhưng trên một store đã giữ hàng giờ
traffic sạch thì mẫu số 6 giờ cần khoảng hai mươi phút để vượt 5.6 — đo được 5.30.

**Bài học:** hoá ra làm con số *mạnh* hơn — 1h/5m là cặp đã hiệu chuẩn. Guide đã sửa và ghi 5.30 làm lý do. Một sự
cố phụ cùng họ: khối diagnostic thiếu `max without (sloth_window)` nên báo "không cặp nào từng đúng" *trong khi*
alert nó đang chẩn đoán vẫn đang bắn — chính burn rate in ra ngay cạnh phản bác nó, và đó là lý do khối in cả hai.

> "I predicted the page in about four minutes and it took nine and a half. I had reasoned that the 6h/30m pair
> would win because its threshold is lower, but its denominator is six hours of mostly clean traffic, so it
> needed roughly twenty minutes to climb past 5.6 — it measured 5.30. The 1h/5m pair fired first. That makes
> the result *stronger*, not weaker: the fast pair is the calibrated one, and the slow pair is there for slow
> burns. I corrected the expected value in my own procedure and recorded 5.30 as the reason, because a
> prediction that was wrong is worth more written down than quietly deleted."

</details>

<details>
<summary>6 · Node thứ ba đã tồn tại mà vẫn không nhận được pod</summary>

**Triệu chứng:** `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu` — **bốn mươi giây
sau khi pod bị `Pending`**, tức đúng lúc node thứ ba vừa lên `Ready`.

**Nguyên nhân:** node còn taint khởi tạo. Tồn tại không đồng nghĩa với nhận việc được.

**Bài học:** đó là lý do node tính bằng phút chứ không bằng giây, và lý do guide giữ đỉnh ramp mười phút. Một ramp
ngắn hơn kết thúc khi node còn taint, và cả lần chạy sẽ được đọc thành "autoscaler không phản ứng" — **một kết luận
sai từ một phép đo đúng**.

> "Forty seconds after the pod went Pending, the scheduler said `0/3 nodes are available: 1 node had an
> untolerated taint, 2 insufficient cpu`. The third node existed and was Ready — it still carried its
> initialisation taint. Existing is not the same as being able to take work. Two consequences: node scale-out
> is measured in minutes, not seconds, and the load test holds its peak for ten minutes. A shorter ramp would
> end while the node is still tainted, and I would have read the whole run as *the autoscaler did not react* —
> a wrong conclusion from a correct measurement."

</details>

---

## Bảy câu xuyên suốt, không thuộc dòng nào

<details>
<summary>Project này tốn bao nhiêu, và anh cắt gì trước?</summary>

Một cụm đang chạy tôi **ước tính 0.4–0.6 USD một giờ** — ước tính, tôi chưa đọc Cost Explorer cho một phiên nào.
Khoản không tắt được là control plane của EKS; cộng NAT gateway, hai ALB, node Spot. Nền tảng chạy trên tín dụng Free
plan, **91.64 USD còn lại tính tới 22/09**, dùng chung với project Medical, và account bị đóng khi tiêu hết.

Budget đặt theo cách đáng nói: nó cảnh báo trên phần chi của **riêng** Anime, **tính trước khi trừ tín dụng** —
`include_credit = false` — nên nó bắn *trong lúc* tín dụng vẫn đang trả tiền.

Và đây là câu đáng nhớ nhất: ở đúng mức tải tôi đã đo, **nền tảng tốn mỗi giờ nhiều hơn model tốn mỗi nghìn
request**. Nó đảo ngược trực giác mà con số `$0.42` tạo ra, và nó là lý do thật của việc huỷ cụm khi không dùng — cũng
là lý do không SLO nào ở đây được phép nói là "đã đạt".

> "Estimated at forty to sixty cents an hour — estimated, not measured; I have not read Cost Explorer for a session.
> It runs on ninety-one dollars of Free-plan credit shared with my other project, and the budget alarm counts spend
> *before* credits, so it fires while the credit is still paying. The line worth saying: at the volumes I measured,
> the platform costs more per hour than the model costs per thousand requests."

</details>

<details>
<summary>Điểm yếu lớn nhất của project là gì? Anh sửa cái nào trước?</summary>

Xếp theo mức tôi thấy nghiêm trọng:

1. **Prometheus và Alertmanager không có xác thực nào**, nên mọi peer VPN và mọi pod trong VPC đặt được silence —
   một silence sai chỗ làm im luôn cái page mà cả stage SLO tồn tại để tạo ra. Sửa trước, và sửa bằng NetworkPolicy
   theo `ipBlock` của subnet ALB nội bộ trước, rồi OIDC ở tầng ALB.
2. **Không có dead-man's-switch**, nên đường alert chết trong im lặng.
3. **Một NAT gateway** là điểm gãy duy nhất cho mọi thứ pod gọi ra ngoài — provider, Hugging Face, Langfuse *và*
   webhook Discord. Một sự cố zone vừa làm service lỗi vừa làm im đường báo tin về nó.
4. **Phép đo capacity có điều kiện hợp lệ trượt**, nên chỉ nói được cái trần.
5. **Chưa có phép đo dựng lại có bấm giờ** (M8).

Ba cái đầu là *thiết kế*, không phải lỗi — chúng nằm trong bảng rủi ro §10 hoặc trong cột false pass của §6, chứ
không phải được tìm ra sau. Nói vậy **không** hạ thứ tự: tôi vẫn sửa xác thực trước, và câu "làm sao anh biết
Prometheus đã chết sáu tiếng" bên dưới là mở rộng của **mục 2** trong danh sách này, không phải một câu trả lời
khác cho cùng câu hỏi.

> "The missing authentication on Prometheus and Alertmanager, because a misplaced silence mutes the very page the
> SLO stage exists to produce — and it is exploitable from any pod in the VPC. Then the absent dead-man's-switch,
> then the single NAT gateway, which is a shared point of failure for the provider *and* the Discord webhook."

</details>

<details>
<summary>Anh dựng hệ này hai lần — EKS và kubeadm. Chọn cái nào, và cái khó dạy anh gì?</summary>

Chia vai có chủ ý. **kubeadm** (Medical) để tự sở hữu control plane: etcd, chứng chỉ, backup, nâng cấp. **EKS**
(project này) để dồn sức vào phần phía trên: SLO burn-rate, canary tự rollback, autoscaling theo in-flight, tracing
và chi phí LLM.

Chọn gì ở chỗ làm có team: **EKS**, gần như luôn luôn. Tự quản chỉ khi cần kiểm soát thứ EKS không mở ra.

Cái bên khó dạy được mà bên dễ không dạy: một *phép kiểm* có thể pass sai. Ở Medical, health check đầu tiên chỉ đọc
`Healthy` và nó pass trong khi nền tảng chưa lên — tốn một chứng chỉ Let's Encrypt để phát hiện. Ở EKS tôi sẽ không
bao giờ gặp chỗ đó, và cũng sẽ không bao giờ học được nó. Và chính bài học ấy là lý do project này có một trang riêng
chỉ để nói **điều kiện** của từng con số.

> "Deliberate split: kubeadm to own the control plane, EKS to spend the time above it — SLOs, canaries, autoscaling,
> LLM cost. For a team I would choose EKS almost every time. What the hard one taught me is that a check can pass
> falsely, and it cost a Let's Encrypt issuance to find out. That lesson is why this project has a page whose only
> job is to state the conditions of every number."

</details>

<details>
<summary>Error budget hết thì làm gì? Ai quyết định dừng release?</summary>

SLO và các hệ số burn rate thì có; **policy thì không có**, và tôi nói thẳng chuyện đó. Trên một nền tảng một người
với cụm bị huỷ mỗi tối, một quy tắc "budget dưới mức X thì dừng làm tính năng" chỉ là diễn.

Thứ đầu tiên tôi viết nếu làm trong team: đúng quy tắc đó, kèm người sở hữu nó — vì một burn-rate alert không có
policy đằng sau chỉ là một alert tỉ lệ lỗi to tiếng hơn.

> "The SLO and the burn-rate factors exist; the policy does not, and I would say so. On a one-person platform with a
> cluster torn down nightly, a freeze rule would be theatre. On a team it is the first thing I would write — because
> a burn-rate alert with no policy behind it is just a louder error-rate alert."

</details>

<details>
<summary>Làm sao anh biết Prometheus đã chết sáu tiếng?</summary>

Hôm nay thì **không biết**, và đó là lỗ tôi nói thẳng — **mục 2** trong danh sách điểm yếu ở trên, sau phần xác
thực. Không Watchdog, không dead-man's-switch. Và trên nền tảng này
còn tệ hơn: cụm bị huỷ khi không dùng, nên một store trống là trạng thái *bình thường* mỗi sáng chứ không phải dấu
hiệu bất thường.

Lập luận cho việc phải có nằm ngay trong bằng chứng của tôi, ở chỗ khác: tôi đã chứng minh rằng **một cửa sổ rỗng trả
về "không có dữ liệu", không phải "không có lỗi"** — đó là lý do KEDA đặt `ignoreNullValues=false`, và là lý do phép
đếm rò Langfuse phải đo một trace đáng ra phải xuất hiện *trước*. Cùng lập luận áp cho đường alert thì kết luận là:
phải có một alert **luôn luôn** bắn, và cái im lặng mới là thứ gọi người.

Thứ tự tôi thêm: Watchdog ra một dịch vụ ngoài cụm, rồi alert trên chính đường alert.

> "Today I would not, and that is a real gap: no Watchdog, no dead-man's-switch — and here an empty metric store is
> the normal state every morning, not a signal. The argument for one is already in my own evidence elsewhere: an
> empty window returns *no data*, not *no errors*. That is why KEDA has `ignoreNullValues=false`. Applied to the
> alerting path it means there must be an alert that always fires, and the silence is what pages you."

</details>

<details>
<summary>Prod trả 503. Dẫn tôi qua mười phút đầu.</summary>

Thu bằng chứng trước khi đổi gì. **Vừa có gì đổi không** — health và `status.sync` của Application, và một canary
đang chạy thì phân tích phải chặn nó; chưa chặn thì tôi abort tay. Bản vừa promote thì **revert trong Git**, không
`kubectl edit`: self-heal sẽ xoá bản sửa tay. `api_fault_rate` khác 0 nghĩa là một drill còn nằm đó.

Rồi **stage nào hỏng**: `anime_upstream_errors_total` có nhãn `stage`, nên tách được provider hỏng, retrieval hỏng, và
api tự hỏng. Rồi burn rate từng cửa sổ, để biết cặp nào bắn và budget còn bao nhiêu.

Và một cái bẫy riêng của nền tảng này tôi sẽ nói ra: **một NAT gateway** nghĩa là một sự cố zone lấy đi provider,
Hugging Face, Langfuse *và* webhook Discord cùng lúc — nên "im lặng cộng với lỗi" là một giả thuyết về NAT, không
phải một lỗi của alerting.

> "Collect before changing. Did anything change — the Application's sync status, whether a canary is running, whether
> a drill's fault rate is still set; if a release did this the way back is a revert in Git, not a `kubectl edit`,
> because self-heal undoes a manual fix. Then which stage failed, from the `stage` label on the upstream error
> counter. And one platform-specific trap: a single NAT gateway means a zone event takes the provider *and* the
> Discord webhook at once, so silence plus errors is a NAT hypothesis, not an alerting bug."

</details>

<details>
<summary>Anh có câu nào hỏi lại chúng tôi không?</summary>

- Ca trực vận hành thế nào, và trung vị một tuần bị gọi bao nhiêu lần?
- Có error budget policy có hiệu lực thật không, hay chỉ có dashboard?
- Khi một SLO bị vi phạm thì ai sở hữu nó — team làm sản phẩm hay team platform?
- Khoảng bao nhiêu phần trăm một tuần là toil?
- Một thay đổi hạ tầng đi qua pull request, hay đi qua terminal của một người?

Mỗi câu đều có một chỗ trong project này để đỡ nếu bị hỏi lại "sao anh quan tâm cái đó".

</details>

---

[Chế độ đo](modes.md) · [Kiến trúc](architecture.md) · [Thuật ngữ](glossary.md) ·
[Bộ đề](../common/questions.md) · [Evidence](../evidence/)
