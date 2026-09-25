# Thuật ngữ

Hai tầng. **Tầng chọn lọc** ở dưới đây: những từ người phỏng vấn thật sự hỏi, định nghĩa đủ mức nói ra miệng.
**Tầng đầy đủ** ở cuối trang: 74 mục trích thẳng từ tám file `concepts.md` của repo, bấm mở.

Một định nghĩa lỏng là một lời mời đào sâu. Nếu chỉ thuộc được một tầng, thuộc tầng trên.

---

## Chế độ đo

| Từ | Nói thế này |
|---|---|
| **real mode** | Provider thật. Cái đã đo là OpenAI `gpt-4o-mini`; Gemini vẫn chọn được. Mỗi request real mode đi **hai** cuộc gọi ra ngoài: embedding qua Hugging Face, rồi chat. |
| **fake mode** | `LLM_PROVIDER=fake`. **Không có cuộc gọi ra ngoài nào** — embedding thành vector hash tất định, LLM chỉ ngủ. Giữ nguyên thread pool, hàng đợi, histogram; bỏ đi mạng. |
| **`FAULT_RATE`** | Xác suất `FakeLLM` raise lỗi. **Chỉ fake provider đọc nó** — đặt lên rollout real mode thì tiêm zero lỗi, canary khoẻ, và drill bị lưu như bằng chứng sai. |
| **`alert.fault`** | Một **mốc thời gian**, không phải tỉ lệ: lúc bản lỗi nhận toàn bộ traffic. Ghi *sau* vòng poll Healthy, nên `T-PAGE` có thể bị báo thấp hơn thực tế. |
| **Câu luật** | *"A number produced in fake mode and a number produced in real mode are different claims."* Chế độ luôn nằm cùng câu với con số. |

## Đo tải và capacity

| Từ | Nói thế này |
|---|---|
| **Open model / arrival rate** | Gửi theo tốc độ định trước, bất kể service có chậm không. Đối lập với closed model, nơi virtual user chờ câu trả lời mới hỏi tiếp. |
| **Coordinated omission** | Sai số của closed model: request chưa bao giờ được gửi thì chưa bao giờ được tính thời gian, nên độ trễ bị báo nhẹ và điểm gãy trông dịu hơn thực tế. |
| **Dropped iteration** | k6 muốn gửi mà không còn virtual user rảnh. Xảy ra trước điểm capacity thì con số mô tả **máy phát tải**, không mô tả service. |
| **Knee (điểm gãy)** | Điểm p95 tách khỏi mức tải thấp. Định nghĩa **trước khi chạy**: điểm đầu tiên p95 vượt 1.5 lần trung bình bốn điểm p95 đầu. |
| **Trần so với capacity** | Trần = tốc độ **phục vụ** dừng lại trong khi tốc độ gửi vẫn leo (93.9 req/s). Capacity = tốc độ ở điểm ngay trước knee (88–89) — và điều kiện hợp lệ của nó đã trượt, nên chỉ nói trần. |
| **in-flight** | Số request đang được xử lý trong một pod tại một thời điểm. Gauge đọc **tức thời** — khác p95 vốn là trung bình hai phút, và đó là lý do in-flight tại knee không tái lập. |
| **Thread pool** | FastAPI đẩy lời gọi model đồng bộ vào một pool 40 luồng, mỗi luồng giữ một request. Nên **in-flight trên 40 mỗi pod nghĩa là hàng đợi đang hình thành** — một định nghĩa, không phải một phép đo. |
| **p95 và mép bucket** | `histogram_quantile` **nội suy** trong bucket, nên nó khác order statistic của client: 7.07 s phía server so với 6.28 s ở k6, và hai số vẫn nhất quán. |
| **Vì sao T phải là mép bucket** | SLI đếm request nhanh hơn T bằng counter tại `le=T`. Không có bucket 7.07 s, nên T là mép gần nhất giữ được ít nhất 95% request: **8 s**. |

## SLO và cảnh báo

| Từ | Nói thế này |
|---|---|
| **SLI / SLO / error budget** | SLI là phép đo (tỉ lệ request thành công). SLO là mục tiêu đặt lên nó (99.5% trong 28 ngày). Error budget là phần còn lại: 0.5%. |
| **Burn rate** | Tốc độ tiêu error budget so với tốc độ "vừa đủ hết đúng lúc hết chu kỳ". Burn rate 1 là hết đúng cuối chu kỳ; 13.44 là hết trong khoảng hai ngày. |
| **Multiwindow multi-burn-rate** | Một alert là phép **AND** của một cửa sổ dài và một cửa sổ ngắn; page là phép **OR** của hai cặp như vậy. Cửa sổ dài chống báo động giả, cửa sổ ngắn làm alert tắt nhanh. |
| **Vì sao 13.44 chứ không 14.4** | 14.4 / 6 / 3 / 1 là bộ quen thuộc cho chu kỳ 30 ngày. Cùng tỉ lệ budget ấy trên **28 ngày** cho 13.44 / 5.6 / 2.8 / 0.93. |
| **Cặp đã hiệu chuẩn** | Cặp có cửa sổ dài **không dài hơn tuổi của store**. Ở đây chỉ 1h/5m là hiệu chuẩn; hai cặp ticket 1d/2h và 3d/6h giữ nguyên ngưỡng mà đánh giá trên quãng ngắn hơn cái tên nó mang. |
| **Page so với ticket** | Page gọi người **ngay**; ticket là việc của vài ngày tới. Một webhook, một kênh Discord: tiêu đề ghi `[PAGE]` hay `[TICKET]`. Không tách thì mọi thứ thành page, và người ta học cách bỏ qua page. |
| **`group_wait`** | Alertmanager giữ một nhóm mới 30 giây trước khi gửi — nằm trong 9 phút rưỡi, và là lý do biên dưới là 9:30 chứ không 9:00. |
| **Rule được nạp so với được đánh giá** | Một `PrometheusRule` monitoring stack không chọn thì **được nhận và bị bỏ qua** — drill chạy vào đó sẽ im lặng hoàn toàn mà không lỗi ở đâu. Nên phép kiểm là *6 rule group, 34 rule, 0 lần đánh giá thất bại*. |

## Canary

| Từ | Nói thế này |
|---|---|
| **Rollout** | Thay Deployment để chia traffic theo từng phần. KEDA scale được nó vì nó có subresource `/scale`. |
| **AnalysisRun / AnalysisTemplate** | Loạt truy vấn Prometheus phán xử một bước canary. Đủ số lần thất bại thì Rollout tự abort và trả traffic về stable. |
| **`rollouts-pod-template-hash`** | Nhãn phân biệt ReplicaSet canary với stable. Truy vấn phải lọc theo hash của **canary**; lọc theo trung bình toàn service thì 10% traffic xấu bị 90% tốt pha loãng. |
| **`latency-ratio`, không phải "p95 ≤ T"** | T là số real mode, drill chạy fake mode — một cổng tuyệt đối không thể đỏ ở đây. So hai bản đo cạnh nhau thì chế độ bị loại khỏi câu hỏi. |
| **`failureLimit`** | Bằng 1: một phép đo trượt chưa đủ, phải hai lần. Nên một phần của 167 giây là chờ phép đo thứ hai. |
| **`Inconclusive`, và vì sao nó tồn tại** | Argo Rollouts không có điều kiện `inconclusive` riêng, nên cả `successCondition` lẫn `failureCondition` đều mở đầu bằng `len(result) > 0`. Kết quả rỗng không khớp cái nào → rollout **dừng chờ người**, không abort. |
| **Vector rỗng ≠ số 0** | Một truy vấn không khớp series nào trả về *không có gì*. Nếu coi nó là 0 thì "không đo được gì" biến thành một đường phẳng yên tâm. Cùng lập luận là lý do KEDA đặt `ignoreNullValues=false`. |

## Autoscaling

| Từ | Nói thế này |
|---|---|
| **KEDA ScaledObject** | Khai báo trigger; KEDA dịch nó thành một HPA. `ignoreNullValues=false` làm một truy vấn rỗng thành **lỗi** chứ không thành 0 — nếu không, replica giảm vì mất series sẽ trông giống giảm vì hết tải. |
| **HPA stabilisation window** | 300 giây trước lần giảm đầu: một quãng lặng ngắn không được phép làm co một cluster sắp cần lại công suất. |
| **Cluster Autoscaler** | Thêm node khi có pod `Pending` vì thiếu chỗ; và **không xoá node trong mười phút** sau khi thêm. Đo được: node bị xoá 26 phút 16 sau khi được thêm. |
| **Taint khởi tạo** | Node mới `Ready` mà vẫn mang taint nên chưa nhận pod. Tồn tại không đồng nghĩa với nhận việc được — đó là lý do node tính bằng phút, không phải giây. |
| **Request so với usage** | Scheduler xếp pod theo cái nó **xin**, và Cluster Autoscaler thêm/bớt node theo cùng thước đó. 0.23 core đo được là *usage*; 250m là *request*. |
| **Vì sao không scale theo CPU** | Tại đúng cái trần, mỗi pod dùng 0.23 core — luồng đang **ngủ chờ provider**, không phải đang tính. Một HPA theo CPU thấy service rảnh đúng lúc p95 nhảy từ 1.43 s lên 15.6 s. |

## GitOps

| Từ | Nói thế này |
|---|---|
| **Application (Argo CD)** | Object nói "cài *cái này* từ Git hoặc chart, vào *namespace kia*". |
| **App-of-apps** | Một Application (`root`) mà việc duy nhất là tạo ra các Application khác. |
| **Sync wave** | Thứ tự áp dụng; wave sau chỉ chạy khi mọi Application wave trước `Healthy` **và** `Synced`. |
| **`Synced` so với `Healthy`** | `Healthy` là **mặc định vô điều kiện** cho resource Argo CD không có health check, nên một cây `Healthy` vẫn có thể đang lệch khỏi Git. Phải đòi cả hai. |
| **`Synced` chính xác là khớp với gì** | Khớp với **revision Argo CD đang giữ trong cache**, không phải với `main` trên GitHub. False pass là đúng chiều này: repo-server mất đường ra GitHub, cache còn commit cũ, và Application vẫn đọc `Synced` — *đang khớp một bản Git cũ*. (`ComparisonError` là ca **dễ**: nó lộ ra ngay.) Nên phép kiểm thật là so `status.sync.revision` với `git rev-parse origin/main` **sau một `git fetch`** — so với commit mình vừa push, không phải với danh sách ref. |
| **`ignoreDifferences`** | Field Argo CD không tính là drift. `Rollout ["/spec/replicas"]` nằm ở đây; thiếu nó thì Git nói 2 và cả lần scale-out bị hoàn tác trong vài giây. |
| **`Degraded` là câu trả lời đúng** | Sau một lần abort, Application đọc `Synced/Degraded` — Git vẫn yêu cầu bản lỗi, cluster đã từ chối. Argo CD **không** chữa, vì chữa nghĩa là thử lại bản vừa bị từ chối. Rollout sở hữu quyết định abort, Git sở hữu ý định. |

## Chuỗi cung ứng

| Từ | Nói thế này |
|---|---|
| **Tag so với digest** | Tag di chuyển được; digest là hash của manifest, không đổi. CI đẩy theo **tag** rồi đọc digest về — và **digest** là thứ Git ghi và chữ ký ký lên. |
| **Fixable** | Lỗ hổng **có** bản vá. Gate chỉ đếm loại này: chặn build vì một CVE chưa ai vá thì chỉ tạo ra thói quen bỏ qua gate. |
| **Positive control** | Một lần chạy **cố ý** làm gate đỏ. Gate xanh mãi cũng không chứng minh nó biết đỏ. Ở đây: hạ ngưỡng xuống MEDIUM thì gate đỏ với 5 finding có bản vá mỗi image. |
| **cosign keyless** | Ký bằng token OIDC của workflow thay vì private key. Danh tính ký là URL của workflow và ref — `ci.yml@refs/heads/main` — và bản ghi nằm trên **Rekor công khai**. |
| **SBOM attestation** | Bảng kê thành phần của image, ký và gắn kèm **digest**. Được sinh và lưu; chưa có cổng nào *tiêu thụ* nó. |
| **`ci-ok`** | Required status check **duy nhất** chặn merge. Phép kiểm index âm chạy ở một workflow riêng. |

## AWS và EKS

| Từ | Nói thế này |
|---|---|
| **Private-only endpoint** | EKS **vẫn cấp một tên DNS public**, nhưng với `endpointPublicAccess=false` tên đó chỉ resolve ra địa chỉ private. Cái không tồn tại là *địa chỉ*, không phải *cái tên*. |
| **SSM port forwarding** | Session Manager mở cổng qua agent trên EC2 — không bastion mở cổng 22, không SSH key. Máy đích của tunnel chính là gateway WireGuard tôi vốn cần cho UI nội bộ. |
| **EKS Pod Identity** | Gắn ServiceAccount với IAM role bằng một association của EKS. Ở đây có **sáu**: ALB controller, External Secrets, EBS CSI, Cluster Autoscaler, external-dns, Argo Rollouts. Khác IRSA ở chỗ không cần OIDC provider cho từng cluster. |
| **Stack theo vòng đời** | `destroy` luôn xoá trọn một state file, nên state chung là vòng đời chung. `cluster` đọc `shared` qua data source và **không bao giờ ghi vào** — nhờ chiều đó, lệnh huỷ chỉ với tới được thứ nó được phép huỷ. |
| **Spot** | Công suất EC2 dư giá rẻ, AWS lấy lại được với thông báo hai phút. Managed node group xử lý thông báo đó; **PodDisruptionBudget chỉ ăn vào eviction tự nguyện**, không ăn vào một lần thu hồi đột ngột. |
| **ACM** | AWS cấp và tự gia hạn chứng chỉ, gắn vào ALB bằng annotation. Cluster không giữ private key nào cho hai tên public — khác hẳn cert-manager ở project Medical. |

## Tracing và chi phí

| Từ | Nói thế này |
|---|---|
| **Filter theo *resource*, không theo span** | Pipeline Langfuse lọc trên `resource.attributes["anime.llm.provider"]`. Resource attribute đặt một lần cho cả process, nên nó giữ hoặc bỏ **toàn bộ** span của một pod — span retrieval đi kèm span generation. Đã chứng minh: *chế độ của pod* quyết định pod có vào Langfuse hay không. **Chưa** chứng minh: một bộ lọc theo từng span. |
| **OTLP, và fan-out** | Một luồng span vào collector, hai pipeline ra, mỗi pipeline có filter riêng. Nhờ tách vậy mà lần hỏng đầu đọc được: Tempo giữ trace đầy đủ trong khi Langfuse trống — tách được "app không sinh trace" khỏi "trace không export được". |
| **Exemplar** | Một trace id gắn kèm một mẫu histogram, để một điểm trên biểu đồ độ trễ mở ra đúng trace đằng sau nó. |
| **`GENERATION` observation** | Kiểu span của Langfuse cho một lượt gọi model, mang model, token vào/ra và chi phí. |
| **Connector spanmetrics** | Biến span thành metric, và **Prometheus scrape cổng `8889` của collector qua PodMonitor** — collector không đẩy metric đi đâu. Nguồn của con số 6076 span, và là cách chứng minh trace *có tồn tại* trong lúc Langfuse trống. |
| **Đừng đo sự vắng mặt** | Muốn chứng minh trace fake không rò sang Langfuse thì **không** đếm số 0. Đo một thứ đáng ra phải xuất hiện *trước*: một trace thật tạo **sau** trace fake; khi nó đã hiện, ingestion đã vượt mốc đó. |
| **Vì sao giá phải kèm ngày** | Giá không có trong API nào; nó nằm trên một trang web không hiển thị ngày sửa. Một con số chi phí không kèm ngày đọc giá thì không tái lập được. |

## Xuyên suốt

| Từ | Nói thế này |
|---|---|
| **False pass** | Trạng thái nhìn như đạt trong khi thứ được kiểm đang hỏng. Mỗi tiêu chí trong project này phải nêu false pass của nó — vì một phép kiểm không thể trượt thì không phải một phép kiểm. |
| **Positive control và negative test** | Cùng một ý ở hai chỗ: một lần chạy cố ý dựng sao cho phép kiểm đang hoạt động **phải** đỏ. Evidence gọi lần làm phép kiểm index đỏ là *negative test*. |
| **Cấu hình không phải phép đo** | *"SLO defined at 99.5%"* đúng từ ngày commit; *"sustained 99.5%"* thì không, và sẽ không bao giờ đúng trên một cluster bị huỷ khi không dùng. |

---

## Vốn từ tiếng Việt của bộ đề

Mười dòng này là quy ước đặt tên của từng bộ câu hỏi, ở đầu mỗi `answers.md`. Chúng là **vốn từ ta đang thật sự
nói**, nên trang này dùng đúng chúng.

| Bộ | Quy ước |
|---|---|
| **common** | **phase app** cho phần đã làm · **stage** cho tám giai đoạn hạ tầng · **tiêu chí** cho mười sáu điều kiện hoàn thành · **pass sai** cho một phép kiểm xanh trong khi thứ nó canh đang hỏng |
| **Terraform** | **stack** cho cả `shared`, `cluster`, `bootstrap` · **tunnel** cho port-forward qua SSM · **phép kiểm** cho một check · **huỷ** cho `destroy` |
| **GitOps** | **cửa** cho một load balancer · **nửa âm / nửa dương** cho hai nửa của #16 (tắt VPN phải thất bại / bật VPN phải thành công) |
| **CI/CD** | **gate** cho phép kiểm chặn được build · **positive control** cho lần chạy cố ý dựng sao cho gate phải đỏ |
| **Đo tải** | **baseline** cho lần chạy real mode để đọc T · **ramp** cho lần chạy capacity ở fake mode · **điểm gãy** cho chỗ p95 tách khỏi p95 tải thấp |
| **Canary** | **gate** cho một điều kiện trong phân tích · **lần đo** cho một measurement · **hash** cho `rollouts-pod-template-hash` · **drill** cho lần cố ý chạy promote hay rollback |
| **SLO** | **cặp** cho một cửa sổ dài ghép một cửa sổ ngắn · **page** / **ticket** cho hai mức severity · **drill** cho lần cố ý tiêm lỗi |
| **Autoscaling** | **in-flight** cho số request đang xử lý · **trigger** cho điều kiện KEDA đọc · **scale out / scale in** cho thêm / bớt |
| **Tracing** | **span retrieval** và **span generation** cho hai span viết tay · **nơi nhận** cho Tempo hoặc Langfuse · **dấu** cho resource attribute đánh chế độ của pod |
| **AWS** | **self-managed** cho cụm kubeadm của Medical · **managed** cho EKS · **gánh vận hành** cho việc phải làm đi làm lại để một thứ tiếp tục chạy |

---

## Bản đầy đủ — 74 mục, trích từ tám file `concepts.md`

Trích bằng script từ chính repo, giữ nguyên tiếng Anh vì đây là bản để **tra**, không phải để học nói: mỗi mục là
tiêu đề `## <n>.` cộng câu đầu của `**What it is.**`. Đoạn đầy đủ nằm cách một cú bấm trong repo.

Các file này **định nghĩa mỗi khái niệm đúng một lần** — "burn rate" chỉ có ở `6-slo`, `digest` chỉ có ở `3-cicd`,
`KEDA` chỉ có ở `7-scaling`. Chỗ nào cần lại thì file **trỏ sang** chứ không định nghĩa lần hai.

<details>
<summary><strong>Terraform — 10 mục</strong> (<code>1-terraform/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | State, configurations and a blast radius | Terraform keeps a *state* file that maps each resource in the code to the real object it created. |
| 2 | Providers, and why apply order is not optional | A *provider* is the plugin Terraform uses to talk to one API — AWS, Kubernetes, Helm. |
| 3 | Refresh, drift and a saved plan | Before planning, Terraform normally *refreshes*: it asks the real APIs what each resource looks like now. |
| 4 | A managed control plane | A Kubernetes control plane is the API server, etcd, the scheduler and the controller manager. |
| 5 | Public and private endpoints, and the name on the certificate | The API server is an HTTPS endpoint. |
| 6 | Spot capacity and the disruption budget | Spot is spare EC2 capacity at a large discount, which AWS can take back with a two-minute **interruption notice**. |
| 7 | Workload identity: Pod Identity, IRSA and the node role | Three ways a pod can get AWS permissions without a stored key: |
| 8 | OIDC federation for CI | GitHub Actions can request a short-lived token describing the running workflow: the repository, the branch, the event. |
| 9 | ACM, and what renewal depends on | AWS's certificate service. |
| 10 | WireGuard and SSM port forwarding | *WireGuard* is a VPN: each side holds a keypair, and packets that do not authenticate are dropped without a reply, so a scan sees nothing. |

</details>

<details>
<summary><strong>GitOps — 11 mục</strong> (<code>2-gitops/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | GitOps, pull not push, and the app-of-apps | GitOps means the desired state of the cluster is a directory in Git, and a controller inside the cluster keeps pulling it and making the cluster match. |
| 2 | Custom resources and their definitions | Kubernetes can be taught new kinds of object. |
| 3 | Sync waves, and the health check that makes them wait | A *sync wave* is a number on an object. |
| 4 | What Healthy means to Argo CD | Argo CD reports two things per Application: *Synced* — the cluster matches Git — and *Healthy* — the objects are working. |
| 5 | The AWS Load Balancer Controller, and IngressGroups | A controller that watches Ingress objects and builds AWS load balancers from them. |
| 6 | Target type, health checks and readiness gates | A target group registers either *instances* — nodes, reached through a node port — or *IPs* — pods, reached directly. |
| 7 | TLS at the edge | *TLS termination* is where the encrypted connection ends and plain traffic begins. |
| 8 | External Secrets | A controller that reads values from an external store and writes them into Kubernetes Secrets. |
| 9 | Alias records and external-dns | An *alias record* is Route 53's way of pointing a name at an AWS resource such as a load balancer; it needs that resource's DNS name and zone id when it is written. |
| 10 | A public name for a private address | A record in a public zone whose value is a private address. |
| 11 | Telling an app its own name | Web applications build absolute links and redirects from the name and scheme they think they are served on. |

</details>

<details>
<summary><strong>CI/CD — 10 mục</strong> (<code>3-cicd/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | CI and CD as separate jobs | *Continuous integration* turns a change into a verified artefact. |
| 2 | A digest, not a tag | A *tag* such as `v1.4` is a movable name in a registry. |
| 3 | A check wired to fail | A check whose failing case has been produced on purpose and seen. |
| 4 | Vulnerability scanning, and a gate that can fail | A scanner lists known vulnerabilities in an image's packages, each with a severity and sometimes a fixed version. |
| 5 | SBOM and attestation | An *SBOM* (software bill of materials) lists every package in an image. |
| 6 | Keyless signing | Sigstore's way of signing without a long-lived key. |
| 7 | Verifying a keyless signature | Checking that the certificate chains to Sigstore's root, that the signature is in the log, and — since there is no fixed key to compare against — that the identity in the certificate and the issuer that vouched for it are the ones expected. |
| 8 | The bot commit, and a pipeline that cannot trigger itself | A commit made by the pipeline, to the branch the pipeline listens to — so it could start the pipeline again. |
| 9 | Forks and secrets | A pull request from a fork runs without the repository's secrets, because its code was written by someone outside the project and has not been reviewed. |
| 10 | An evaluation gate, and its baseline | A check on *quality* rather than correctness: run fixed questions with known good answers, compute a score, fail if it drops below a stored baseline. |

</details>

<details>
<summary><strong>Đo tải — 8 mục</strong> (<code>4-load/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | A histogram, and what a bucket boundary means | A Prometheus histogram does not store each request's latency. |
| 2 | Percentiles, and how many samples they rest on | The 95th percentile is the value below which 95% of observations fall. |
| 3 | Client-side and server-side latency | *Client-side* latency is measured by the sender. k6's request duration covers sending, waiting and receiving on an already-open connection; it times DNS, connecting and the TLS handshake separately, and with keep-alive those happen once per connection, not per request. |
| 4 | How Prometheus finds a target | Prometheus only collects from *targets* it is configured to scrape. |
| 5 | Open and closed load models | A *closed* model simulates a fixed number of users, each waiting for its answer before asking again. |
| 6 | Saturation, and where it can come from | *Saturation* is where adding load adds latency or errors instead of throughput. |
| 7 | The fake provider as a load source | A mode of the api that answers without calling a model, with a configurable latency and error rate. |
| 8 | An empty result is not a zero | A Prometheus query over data that does not exist returns an *empty result* — no series at all. |

</details>

<details>
<summary><strong>Canary — 9 mục</strong> (<code>5-delivery/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | A Rollout instead of a Deployment | A `Rollout` is Argo Rollouts' replacement for a Deployment. |
| 2 | Canary steps and traffic weights | A *canary* runs the new version beside the old and sends it a share of traffic. |
| 3 | An AnalysisRun, and its three outcomes | An *AnalysisTemplate* defines measurements — a query, how often, how many times — and conditions for success and failure. |
| 4 | The pod-template-hash, and getting it onto a series | Each ReplicaSet a Rollout creates stamps its pods with a `rollouts-pod-template-hash` label, unique to that version's pod template. |
| 5 | A query window and the scrape interval | `rate()` over a window estimates how fast a counter grew, from the samples inside that window. |
| 6 | A relative gate | A gate that compares the new version with the old — *is the canary's p95 more than some ratio of the stable version's?* — rather than with a fixed number. |
| 7 | The resolution of a threshold | A threshold can only be as fine as the measurement under it. |
| 8 | Abort, and what Git says afterwards | When an analysis fails, the Rollout *aborts*: the canary is scaled down and all traffic returns to the stable version. |
| 9 | Fault injection that actually injects | Deliberately making a version fail, to prove the system reacts — with the injection itself verified, or the drill proves nothing. |

</details>

<details>
<summary><strong>SLO — 9 mục</strong> (<code>6-slo/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | SLI, SLO and error budget | A *service level indicator* is a ratio of good events to all events — requests that succeeded, requests faster than a target. |
| 2 | Burn rate | How fast the error budget is being spent, relative to spending it exactly over the objective's period. |
| 3 | Multiple windows, and why two per alert | A *multi-window* alert computes the burn rate over a long window and a short one — about a twelfth as long — and fires only when both exceed the threshold. |
| 4 | Page and ticket | Two severities with two costs. |
| 5 | Generated rules, committed | Sloth takes a short SLO spec and generates the recording rules that compute burn-rate ratios and the alert rules that fire on them, with factors derived from the objective's period. |
| 6 | A window older than the data | A range query such as `rate(x[3d])` is computed from whatever samples fall inside the window. |
| 7 | Time-to-alert, and what it is made of | The time from a fault beginning to a person being told. |
| 8 | A runbook written before the alert | A short entry for each alert: what it means, how to confirm it, what to do first. |
| 9 | Proving delivery, not just firing | Showing that a specific alert reached a person, as distinct from a rule firing or some message reaching a channel. |

</details>

<details>
<summary><strong>Autoscaling — 8 mục</strong> (<code>7-scaling/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | Scaling on the signal that tracks demand | An autoscaler adds replicas when a metric crosses a target. |
| 2 | KEDA and the HPA underneath | The *Horizontal Pod Autoscaler* is Kubernetes' replica controller: on each sync it reads a metric, compares it with a target and sets the replica count. |
| 3 | Little's law | In a stable system, the average number of requests in progress equals the arrival rate times the *average* time each spends inside: *L = λ × W*. |
| 4 | A control loop and its delays | A *control loop* measures, decides and acts, then measures again. |
| 5 | Scale-down and the stabilisation window | The HPA does not remove replicas the moment the metric falls. |
| 6 | What happens when the metric disappears | A Prometheus query that finds no series returns an empty result, and an autoscaler has to decide what that means. |
| 7 | Pods and nodes: two autoscalers | Pod autoscaling adds pods; it cannot add machines. |
| 8 | Scaling during a canary | When the scaled object is a Rollout mid-canary, the canary's ReplicaSet is sized to its weight times the replica count, and the stable ReplicaSet stays at full size so that an abort can return all traffic at once. |

</details>

<details>
<summary><strong>Tracing — 9 mục</strong> (<code>8-tracing/concepts.md</code>)</summary>

| § | Khái niệm | What it is (câu đầu, nguyên văn) |
|---|---|---|
| 1 | A trace and its spans | A *trace* is the record of one request's path through a system, made of *spans*: timed pieces of work, each with a name, a parent and attributes. |
| 2 | OpenTelemetry and the collector | OpenTelemetry is a vendor-neutral standard and set of libraries for producing traces, metrics and logs. |
| 3 | GenAI semantic conventions | *Semantic conventions* are OpenTelemetry's agreed attribute names. |
| 4 | Pipelines and a filter | In the collector, a *pipeline* joins receivers to exporters through its own list of processors. |
| 5 | Span metrics, and two tools that disagree | A span-metrics connector counts spans and records their durations as metrics. |
| 6 | Capturing content | Recording the prompt and the model's response as span attributes, so a trace shows *what* was said as well as how long it took. |
| 7 | Tokens and the cost of a request | Models are billed per token, at different prices for input and output. |
| 8 | An attribute that is present and zero | A value written with a default when the real value is missing looks, downstream, exactly like a real value that happens to be zero. |
| 9 | Where traces live | A trace backend stores traces somewhere and keeps them for some time. |

</details>

---

[Chế độ đo](modes.md) · [Dòng CV](cv-lines.md) · [Kiến trúc](architecture.md) ·
[Bộ đề](../common/questions.md)
