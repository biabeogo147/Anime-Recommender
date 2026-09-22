# Đáp án AWS: managed so với self-managed

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Terraform A5.2` trỏ tới bộ tương ứng của Anime.

Phía Medical **đã dựng và đã chạy** — kể bằng kinh nghiệm được, nhưng chỉ những gì evidence của Medical ghi. Phía Anime
**mới thiết kế, chưa dựng** — kể bằng "tôi thiết kế", "tôi chọn". Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật;
ghi chú **[kiểm chứng]** là hành vi của dịch vụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **self-managed** cho cụm kubeadm của Medical; **managed** cho EKS và các dịch vụ
AWS thay thế một thứ mình tự vận hành; **gánh vận hành** cho việc phải làm đi làm lại để một thứ tiếp tục chạy; **role**
cho IAM role.

**Số liệu đã có** — của Medical, từ evidence của Medical, được phép nói:

| Số | Giá trị | Dùng ở |
|---|---|---|
| Dựng lại toàn bộ nền tảng Medical từ stack rỗng | 14 m 11 s | A2.1 |
| Chi phí Medical khi chạy | khoảng 0.53 USD/giờ | A2.6 |

**Còn phải điền:**

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| RTO khôi phục etcd của Medical | Drill khôi phục etcd của Medical | A2.1 |
| Thời gian dựng lại cụm EKS từ con số không | Lần dựng đầu của Anime | A2.1 |
| Chi phí Anime mỗi giờ khi chạy | Lần dựng đầu của Anime | A2.6 |
| Gói tài khoản có cho EKS, Spot và các loại instance đã chọn không | Kiểm trước khi dựng Anime | A6.2 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Vì một project không dạy tốt được cả hai thứ: vận hành cụm, và vận hành service chạy trên cụm.
Medical tự dựng cụm bằng kubeadm, nên trọng tâm là vận hành cụm: etcd, chứng chỉ, nâng cấp, chuỗi cung ứng. Anime dùng EKS,
nên trọng tâm dời sang vận hành service: SLO, canary, autoscaling, quan sát LLM. Medical tôi đã dựng và chạy; Anime tôi mới
thiết kế."

**Mẹo:** câu cuối quan trọng. Nói rõ bên nào đã chạy, bên nào mới thiết kế, ngay từ đầu.

**A1.2** **Ý chính:** "Năm chỗ chính. Cụm: kubeadm trên EC2 so với EKS với node group Spot. CI: Jenkins trong cụm
so với GitHub Actions. Ký image: khoá KMS so với keyless. Danh tính pod: IRSA dựng tay so với Pod Identity. Chứng
chỉ: cert-manager với Let's Encrypt so với ACM. Kéo theo: ingress khác nhau, Medical có hai môi trường còn Anime
dùng canary thay môi trường dev, và Kyverno với vận hành etcd chỉ có ở Medical."

**A1.3** **Ý chính:** "Chuyển *gánh vận hành* của một thành phần, không chuyển trách nhiệm về kết quả. AWS chạy
control plane, cấp và gia hạn chứng chỉ, chạy agent cấp credential cho pod; tôi vẫn phải cấu hình đúng, giới hạn
quyền đúng, và chứng minh nó chạy. Một policy IAM quá rộng trên EKS vẫn là lỗi của tôi."

### A2. Control plane: kubeadm so với EKS

**A2.1** **Ý chính:** "Với kubeadm, tôi lo API server, etcd, scheduler và controller manager trên ba máy, quorum
của etcd, backup etcd, chứng chỉ của control plane — hết hạn sau một năm, phải gia hạn — và nâng cấp. Ở Medical,
dựng cụm là một playbook Ansible nhiều role, và dựng lại toàn bộ nền tảng từ stack rỗng đo được 14 phút 11 giây.
Snapshot etcd và drill khôi phục là việc đang làm ở giai đoạn vận hành tiếp theo. Với EKS, AWS chạy cả bốn thành
phần đó; tôi không đăng nhập vào máy control plane nào và không vá chúng — còn AMI của worker thì vẫn là việc của
tôi."

*Nếu được hỏi thêm:* RTO khôi phục etcd của Medical `[điền: RTO]`; thời gian dựng lại EKS `[điền: thời gian dựng lại]`.

**A2.2** **Ý chính:** "Truy cập trực tiếp vào etcd — không có snapshot nào để lấy, nên khôi phục trên EKS nghĩa
là dựng lại từ Terraform và Git. Cờ của API server, admission plugin, audit policy. Metric của etcd. Chứng chỉ
của API server. Và một khoản phí cố định cho control plane, kể cả khi không có gì chạy."

*Nếu được hỏi thêm:* mỗi minor có khoảng mười bốn tháng standard support, rồi extended support với phí control
plane cao hơn nhiều; hết cả hai thì AWS tự nâng **[kiểm chứng: thời hạn và mức phí hiện tại]**. Log của control
plane phải bật riêng mới đẩy vào CloudWatch.

**A2.3** **Ý chính:** "Ở tunnel tới API server. Medical tự sinh chứng chỉ bằng kubeadm nên thêm được `127.0.0.1`
vào danh sách tên; `kubectl` qua tunnel chạy luôn. Chứng chỉ của EKS do AWS cấp, mình không cấp lại được, nên
kubeconfig của Anime phải mang thêm `tls-server-name`. Thiếu nó thì mọi lệnh lỗi sai tên chứng chỉ. Cái trông
giống cụm chết là khi lệnh update-kubeconfig ghi đè địa chỉ server về endpoint private: `kubectl` timeout."

*Nếu được hỏi thêm:* Terraform A3.4.

**A2.4** **Ý chính:** "Ở Medical, cụm đang ghim một bản 1.36 và chưa nâng cấp lần nào. Playbook nâng cấp tôi đã
thiết kế: từng node một, drain, `kubeadm upgrade`, nâng kubelet, uncordon, chờ Ready và Argo CD khoẻ mới sang
node sau. Lần chạy thật là một drill còn lại. Ở Anime, tôi thiết kế nâng theo thứ tự: control plane lên một minor
— AWS làm và không quay lui được — rồi các add-on, rồi node group rolling update, tôn trọng PDB. Tôi ghim minor
để thời điểm nâng minor do tôi quyết; bản vá trong một minor thì AWS tự áp **[kiểm chứng]**."

*Nếu được hỏi thêm:* với Medical, trước khi nâng minor còn một cổng — chart Rancher phải chấp nhận phiên bản đích.

**A2.5** **Ý chính:** "Khi cần thứ EKS không cho: truy cập etcd, cấu hình API server tuỳ ý, chạy ở nơi không có
AWS, hoặc khi việc học chính cách vận hành cụm là mục tiêu — như Medical. Còn khi mục tiêu là chạy service, tự
dựng control plane là trả một gánh vận hành lớn cho một thứ người dùng không bao giờ thấy."

**A2.6** **Ý chính:** "Medical khi chạy tốn khoảng 0.53 USD mỗi giờ. Anime cộng phí control plane của EKS, NAT,
hai ALB và node Spot: `[điền: USD mỗi giờ]`. Cả hai được huỷ khi không dùng, nên thứ đáng so là chi phí mỗi giờ
chạy cộng phần còn lại qua đêm — và với Anime, control plane là khoản không tắt được chừng nào cụm còn."

### A3. Danh tính của pod

**A3.1** **Ý chính:** "Nếu pod tới được dịch vụ metadata thì nó dùng chung role của node. Medical dựng IRSA bằng
tay: một khoá ký ổn định, một OIDC issuer đặt trên S3, một OIDC provider trong IAM, và một role cho mỗi
ServiceAccount; chart tự mount token, không có webhook. Bốn namespace — hai môi trường của app và hai của Jenkins
— chặn địa chỉ metadata bằng NetworkPolicy. Các pod của nền tảng — External Secrets, cert-manager, EBS CSI — thì
vẫn dùng role của node."

*Nếu được hỏi thêm:* Anime chặn ở chính node, bằng IMDSv2 với hop limit 1; Medical chặn theo từng namespace.

**A3.2** **Ý chính:** "Cùng một kết quả — một role cho đúng một ServiceAccount — nhưng không có issuer nào phải
tự host. Thứ thay issuer là một agent chạy trên mỗi node, là một add-on managed. Mọi role có cùng một trust
policy cho dịch vụ Pod Identity, và ràng buộc giữa ServiceAccount với role là một association trong API của EKS —
không phải object Kubernetes, nên nó nằm trong Terraform, không nằm trong Git của Argo CD. Ở Anime, mỗi
controller có một association riêng — kể cả External Secrets, thứ mà ở Medical vẫn dùng role của node."

*Nếu được hỏi thêm:* Terraform A5.2.

**A3.3** **Ý chính:** "Không nên nói vậy. Ở mức ServiceAccount, cả hai cho cùng mức cô lập. Pod Identity ít thứ
để cấu hình sai hơn — không issuer, không khoá ký phải giữ. Nhưng điểm kiểm soát dời đi: trust policy tin dịch vụ
Pod Identity của mọi cụm trong account, nên ai có quyền tạo association và pass role là người quyết định pod nào
được role nào. Tôi nói: ít cấu hình hơn cho cùng một mức cô lập, với điểm kiểm soát nằm ở chỗ khác."

*Nếu được hỏi thêm:* nếu dùng lại một role qua nhiều cụm, có thể khoá bằng session tag theo tên cụm hay namespace
**[kiểm chứng: tên tag]**.

**Mẹo:** câu "ít cấu hình hơn cho cùng một mức cô lập" là cách nói an toàn và chính xác.

### A4. Ký image: keyless so với KMS

**A4.1** **Ý chính:** "Medical giữ một khoá bất đối xứng trong KMS; nửa private không bao giờ rời KMS, nên thứ
tôi tin là IAM — chỉ role CI được ký. Chữ ký không ghi vào log công khai. Anime không giữ khoá nào: mỗi lần ký
dùng một khoá tạm, Sigstore cấp chứng chỉ ngắn hạn gắn khoá đó với danh tính OIDC của workflow, và chữ ký được
ghi vào log public. Verify thì tin vào root của Sigstore và vào danh tính ghi trong chứng chỉ."

*Nếu được hỏi thêm:* hiện cả hai đều chưa có gì trong cụm verify chữ ký. Ở Medical, Kyverno là việc đã lên kế
hoạch; Anime cố ý không verify trong cụm, chỉ verify tay một lần ở tiêu chí #3.

**A4.2** **Ý chính:** "Vì ký keyless *công bố*: digest, repo, workflow và danh tính được ghi vĩnh viễn vào một
log public. Image của Medical là private, và những thông tin đó không có lý do gì để công khai. Ở Anime, repo vốn
public, nên cái giá đó chấp nhận được."

*Nếu được hỏi thêm:* còn một lý do thực tế: Jenkins trong cụm không có sẵn danh tính OIDC mà dịch vụ public của
Sigstore chấp nhận, còn GitHub Actions thì có **[kiểm chứng]**. Chi tiết phía Anime ở CI/CD A4.4.

**A4.3** **Ý chính:** "Tuỳ repo có public hay không — đó chính là lý do hai project chọn khác nhau. Nếu phải một,
với repo public tôi chọn keyless, vì không có khoá nào để mất hay xoay. Nhưng keyless đổi lại một phụ thuộc:
Sigstore không dùng được thì không ký được, và `main` không ship được."

### A5. Chứng chỉ: ACM so với Let's Encrypt

**A5.1** **Ý chính:** "Let's Encrypt cho tối đa năm chứng chỉ mỗi bảy ngày cho cùng một bộ tên. Medical dựng lại
cụm thường xuyên hơn thế, nên sao chứng chỉ ra Secrets Manager và tự khôi phục nó ở một wave sớm mỗi lần dựng lại
— nếu thứ tự khôi phục sai, vài lần dựng là hết quota cả tuần. Với ACM, AWS cấp, xác thực qua Route 53 và gia
hạn; private key không rời ACM. Không có gì để sao lưu, không có thứ tự nào để làm sai."

*Nếu được hỏi thêm:* phạm vi cũng khác. Ở Medical, chứng chỉ Let's Encrypt chỉ phục vụ các UI nội bộ; app là HTTP
trên NLB public. Ở Anime, một chứng chỉ ACM phục vụ cả app public lẫn UI quản trị. Và chính việc sắp thứ tự khôi
phục chứng chỉ ở Medical đã làm lộ lỗi health check của Argo CD — GitOps A9.1.

**A5.2** **Ý chính:** "Vì listener của ALB nhận một ARN của ACM, không đọc được Secret của Kubernetes. Ghép
cert-manager với ALB nghĩa là định kỳ import từng chứng chỉ vào ACM — làm được, nhưng thêm một khâu phải chạy
đều, và nó hết hạn lặng lẽ khi ngừng chạy. Tôi chọn không làm."

**A5.3** **Ý chính:** "Chứng chỉ ACM loại không export được chỉ gắn vào dịch vụ tích hợp của AWS — load balancer,
CloudFront, API Gateway — nên TLS kết thúc ở ALB, và trong thiết kế của Anime đoạn từ ALB tới pod là HTTP trong
VPC. Gia hạn cần bản ghi xác thực còn trong zone. Có thể còn cần chứng chỉ đang được gắn vào load balancer lúc
gia hạn — trên một cụm bị huỷ mỗi tối thì không chắc **[kiểm chứng]**."

*Nếu được hỏi thêm:* Terraform A8.4.

### A6. CI, node, mạng và dữ liệu

**A6.1** **Ý chính:** "Jenkins trong cụm là một thứ tôi phải vận hành: controller, storage, plugin, agent là pod.
Đổi lại, build chạy trong VPC của mình, lấy quyền AWS qua IRSA chứ không dùng khoá dài hạn, và không cần endpoint
public nào — Jenkins tự poll Git. GitHub Actions ít thứ để vận hành hơn, nhưng vẫn phải ghim action, giới hạn
trust OIDC theo đúng nhánh, và quản quyền của bot commit. Cả hai đều là liên kết OIDC vào IAM, chỉ khác bên phát
token."

*Nếu được hỏi thêm:* đường tới production cũng khác. Medical lên prod bằng một pull request — một cổng người. Bot
của Anime commit digest thẳng vào `main`, và canary thay cho cổng người đó. CI/CD A5.1.

**A6.2** **Ý chính:** "Medical chạy ba máy vừa làm control plane vừa làm worker. etcd ba thành viên chịu được mất
một, nhưng Spot thu hồi theo đợt — cùng loại máy, cùng lúc — mất hai là mất quorum, và mỗi máy thay mới còn phải
gỡ thành viên cũ và thêm thành viên mới bằng tay. Nên Spot không hợp. Anime không có control plane nào trên node
của mình, nên node Spot biến mất chỉ là mất capacity, và thiết kế coi đó là một đặc tính phải chịu được."

*Nếu được hỏi thêm:* tài khoản dùng chung với Medical đang ở gói bị giới hạn loại instance. Anime chạy cùng tài
khoản đó, nên danh sách instance Spot của Anime phải qua được ràng buộc này — `[điền: gói có cho EKS, Spot và các
loại đã chọn không]`. Terraform A4.1.

**A6.3** **Ý chính:** "Medical dùng Calico, pod có dải địa chỉ riêng, NetworkPolicy được thực thi — kể cả việc
chặn địa chỉ metadata. Load balancer là NLB do Terraform tạo, đổ vào ingress-nginx qua node port. Anime dùng VPC
CNI, pod lấy thẳng địa chỉ trong VPC — nên kích thước subnet và giới hạn pod mỗi node trở thành chuyện phải tính.
Load balancer do controller trong cụm tạo từ Ingress. Đó là ví dụ rõ nhất của 'managed dời vấn đề đi': vòng đời
của load balancer giờ thuộc về một controller, và teardown phải xoá Ingress trước, không thì load balancer mồ côi
chặn việc huỷ VPC."

*Nếu được hỏi thêm:* design của Anime chưa có NetworkPolicy nào, và với VPC CNI nó chỉ được thực thi khi bật
riêng **[kiểm chứng]**. GitOps A3.2.

**A6.4** **Ý chính:** "Ở Medical, Secret của Kubernetes nằm trong etcd mà không được mã hoá riêng lúc lưu. EKS mã
hoá dữ liệu API bằng KMS theo kiểu phong bì, mặc định ở các phiên bản gần đây **[kiểm chứng]**. Đó là một khác
biệt tự dựng so với managed rất cụ thể: ở cụm tự dựng, mã hoá lúc lưu là một cấu hình mình phải tự thêm."

*Nếu được hỏi thêm:* storage thì cả hai dùng EBS CSI — Medical qua role của node, Anime qua Pod Identity. Volume
EBS gắn với một AZ, nên Anime xoá PVC khi teardown để không để lại volume mồ côi tốn tiền.

### A7. Vẫn là của mình

**A7.1** **Ý chính:** "GitOps với Argo CD và thứ tự wave. Secret từ Secrets Manager qua External Secrets, không
bao giờ trong Git. UI quản trị chỉ qua WireGuard. Tunnel SSM tới API server từ ops workstation. Chia Terraform
theo vòng đời. Và kỷ luật 'một phép kiểm xanh không có nghĩa là thứ nó canh đang chạy'. Managed hay không, những
thứ đó vẫn là việc của mình."

**A7.2** **Ý chính:** "Ba chỗ, đều là của Medical: zone Route 53, ops workstation và bucket state của Terraform —
cộng tài khoản AWS chung. Huỷ stack dùng chung của Medical thì Anime mất bản ghi xác thực chứng chỉ và các tên
cùng lúc. Tôi ghi đó là ràng buộc đã biết thay vì dựng bản thứ hai."

*Nếu được hỏi thêm:* Terraform A8.1.

### A8. Nhìn lại

**A8.1** **Ý chính:** "Managed không xoá công việc, nó đổi hình dạng công việc. Tôi không còn giữ etcd hay chứng
chỉ của API server, nhưng vẫn phải chứng minh cấu hình đúng — và lỗi cấu hình trên dịch vụ managed thường im lặng
hơn, vì không có máy nào để đăng nhập vào xem. Ví dụ: thiếu một tag trên subnet thì Ingress vẫn được tạo nhưng
không bao giờ có load balancer, và không có lỗi nào ở chỗ người ta thường nhìn."

**A8.2** **Ý chính:** "Hỏi lại họ muốn đội mình giỏi về cái gì. Nếu sản phẩm là service, dùng managed và dồn công
sức vào SLO, release an toàn, chi phí. Tự dựng chỉ khi có lý do cụ thể — quy định, môi trường không có cloud, hay
nhu cầu thật sự về control plane — và khi có người để vận hành nó lâu dài."

**A8.3** **Ý chính:** "Gắn chặt với AWS: Pod Identity, annotation của controller load balancer, ARN của ACM, bản
ghi alias của Route 53, Spot trong managed node group. Mang đi được: Argo CD và cấu trúc wave, chart của app,
Rollout và phân tích, KEDA, Sloth và các SLO, OpenTelemetry. Phần mang đi được chính là phần project này muốn dạy
— vận hành service — nên lock-in nằm ở tầng tôi cố ý giao cho AWS."

---

[Câu hỏi](questions.md) · [Design, bảng so sánh](../eks-sre-llmops-design.md#1-goal)
