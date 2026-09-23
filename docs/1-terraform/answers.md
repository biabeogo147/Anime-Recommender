# Đáp án Terraform

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `GitOps A2.3` trỏ tới bộ tương ứng.

Stage này **đã dựng và đã chạy**: criterion #1 đóng ngày 2026-09-22 ([evidence](../evidence/terraform.md)). Nói ở
thì quá khứ được, nhưng chỉ với những gì evidence ghi. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **stack** cho cả `shared`, `cluster` và `bootstrap`; **tunnel** cho
port-forward qua SSM; **phép kiểm** cho một check; **huỷ** cho `destroy`.

**Số liệu đã có:** chưa có số nào cho stage này. Số đo duy nhất của project là của phase app, chạy local
([`../evidence/local.md`](../evidence/local.md)).

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| Số resource dự kiến của từng stack, và tổng | Ghi *trước* lần apply đầu | A1.3, A7.2 |
| Thời gian apply từ con số không, từng stack | Lần dựng đầu | A1.3 |
| Đầu ra của `kubectl get --raw /readyz` qua tunnel | Lần dựng đầu | A7.3 |
| Chứng chỉ được gia hạn hay bị cấp lại | Quan sát sau vài tháng | A8.4 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi đã dựng và chạy trên AWS, criterion #1 đóng. Nó dựng tài khoản AWS để mọi stage sau có chỗ
đứng. Tôi chia Terraform theo vòng đời: thứ phải sống qua mỗi lần teardown — registry, secret, vai trò của CI,
chứng chỉ — nằm một stack; mạng, cụm EKS, node Spot và gateway VPN nằm stack kia, bị huỷ mỗi tối. API server của EKS
không có địa chỉ public nào: tôi vào nó qua một tunnel SSM, và máy đích của tunnel chính là gateway WireGuard mà
tôi vốn cần cho các UI nội bộ. Cả project không có một access key AWS nào."

*Nếu được hỏi thêm:* vì sao chia theo vòng đời ở A2.1, vì sao đóng endpoint ở A3.1, sáu danh tính ở A5.1.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "thiết kế, chưa dựng", rồi trình bày tự nhiên.

**A1.2** **Ý chính:** "Vì ứng dụng đã chạy được và đã đo, nhưng chỉ trên đúng một laptop, dựng bằng tay. Không có
bản thứ hai và không có cách tạo ra bản thứ hai. Trước khi làm SLO hay canary thì phải có một tài khoản dựng lại
được mà không ai phải nhớ đã bấm gì."

**A1.3** **Ý chính:** "Apply từ con số không, rồi plan lại và thấy không có thay đổi nào — đối chiếu với một số
lượng resource tôi ghi ra từ trước. Nó chứng minh cấu hình tái lập được và khớp với thực tế."

*Nếu được hỏi thêm:* số resource dự kiến là `[điền: số resource từng stack và tổng]`, thời gian apply
`[điền: thời gian từng stack]`. Chỗ yếu của tiêu chí này ở A7.1.

**A1.4** **Ý chính:** "Khi chạy, stage này sẽ chứng minh hai điều: tài khoản dựng lại được đúng số resource dự
kiến, và API server trả lời qua tunnel. Có một điều chỉ là suy luận. API server không trả lời từ bất cứ đâu khác —
tôi suy ra từ cấu hình endpoint và security group, chưa có phép kiểm nào cố gọi từ ngoài vào để thấy nó thất bại.
Và ba điều vẫn là giả định: Spot bị thu hồi thì mọi thứ xử lý đúng, chứng chỉ được gia hạn chứ không bị cấp lại, và
việc chia stack đứng vững khi `make down` thật — chỉ lần `make down` đầu tiên mới cho biết."

**Mẹo:** tách ba nhóm — sẽ chứng minh, chỉ suy luận, còn giả định. Người phỏng vấn thường hỏi đúng nhóm giữa.

### A2. Chia theo vòng đời

**A2.1** **Ý chính:** "Vì `destroy` luôn xoá trọn một stack. Mọi thứ chung một file state thì chung một vòng đời.
Cụm được thiết kế để huỷ mỗi tối, nên nếu registry nằm chung thì mỗi sáng phải chạy CI lại trước khi làm được gì,
secret phải dán lại, và chứng chỉ bị cấp mới. Chia stack là trả lời câu hỏi về *thời gian*, không phải về gọn gàng."

**A2.2** **Ý chính:** "`shared` giữ ECR, Secrets Manager, vai trò OIDC của GitHub, budget, chứng chỉ ACM và bản ghi
xác thực của nó. `cluster` giữ VPC, EKS, node group, các liên kết Pod Identity, gateway WireGuard cùng Elastic IP và
bản ghi `vpn.anime` của nó. Câu hỏi quyết định là: `make down` có được phép chạm vào thứ này không?"

**A2.3** **Ý chính:** "Nếu chứng chỉ nằm chung stack với cụm thì mỗi lần dựng lại nó bị *cấp mới*, không phải *gia
hạn*. Trong thiết kế tôi viết rằng AWS tự gia hạn chứng chỉ — với một stack thì câu đó sai mỗi ngày, và không có
gì báo lỗi để lộ ra. Đó là loại sai tôi sợ nhất: một lời khẳng định trông đúng mà không bao giờ bị kiểm."

**A2.4** **Ý chính:** "`cluster` đọc `shared` qua data source, không bao giờ ghi vào. Nhờ vậy lệnh huỷ chỉ với tới
được đúng thứ nó được phép huỷ. `make down` gõ được mà không phải đắn đo."

**A2.5** **Ý chính:** "`bootstrap` cài Argo CD và app gốc, và phải apply sau khi tunnel đã mở. Cái bẫy của nó: các
object của nó chết theo cụm, nhưng *state* của nó thì không. Để state đó lại thì lần `make bootstrap` sau sẽ plan
trên một cụm không còn tồn tại. Nên `make down` phải xoá luôn state đó."

*Nếu được hỏi thêm:* tên `bootstrap` mang nghĩa ngược nhau ở hai repo — ở Medical nó là stack không bao giờ bị huỷ,
ở Anime nó là stack apply sau cùng và bỏ đi đầu tiên.

**A2.6** **Ý chính:** "Medical có ba stack và chia vì lý do riêng: một index tốn quota để dựng lại, secret gõ tay,
một khoá ký mà mất đi là mọi chữ ký cũ vô hiệu. Anime dùng lại hai thứ trong stack thứ ba của Medical — bucket state
và ops workstation — thay vì dựng riêng."

**A2.7** **Ý chính:** "Trong bucket state của Medical, dưới tiền tố `anime/`, mỗi stack một key. Khoá dùng cơ chế
lockfile của chính S3, không cần bảng DynamoDB: hai lần apply cùng lúc thì lần sau phải chờ, không ghi đè được."

### A3. Một API server không có địa chỉ public

**A3.1** **Ý chính:** "Vì một danh sách IP phải *luôn* đúng. IP nhà thì xoay vòng. Và khi danh sách sai, nó không báo
là sai — `kubectl` chỉ treo rồi timeout, y hệt một cụm đã chết. Một cơ chế mà khi hỏng lại báo sai nguyên nhân thì
rất tốn công chẩn đoán. Nên tôi bỏ luôn địa chỉ public, thay vì phải giữ danh sách đó đúng mãi."

**Mẹo:** câu "một danh sách đúng vào ngày viết ra và sai mọi ngày sau đó" dễ nhớ, và người nghe cũng dễ nhớ.

**A3.2** **Ý chính:** "Ops workstation chạy `make tunnel`: một port-forward của SSM Session Manager tới endpoint
private của EKS, với máy đích là gateway WireGuard nằm trong VPC. `kubectl` gọi `127.0.0.1:6443`."

**A3.3** **Ý chính:** "Việc thứ nhất là VPN: đưa laptop vào trong VPC để trình duyệt mở được UI nội bộ. Việc thứ hai
là làm máy đích cho tunnel SSM. Cả hai cùng cần một thứ — một máy của tôi nằm trong VPC — nên một máy làm được cả hai.
Tôi cần nó cho UI trước, rồi nhận ra nó cũng giải luôn bài toán endpoint."

**A3.4** **Ý chính:** "`kubectl` nối tới `127.0.0.1`, còn chứng chỉ của API server ghi tên endpoint thật. Không có
`tls-server-name` thì client từ chối vì sai tên. Medical tự sinh chứng chỉ API server bằng kubeadm nên thêm được
`127.0.0.1` vào danh sách tên. Còn chứng chỉ của EKS do AWS cấp, mình không cấp lại được."

*Nếu được hỏi thêm:* `aws eks update-kubeconfig` ghi đè cả đoạn cluster — `server` quay về endpoint thật và mất luôn
`tls-server-name` — nên phải sửa lại cả hai dòng mỗi lần chạy lệnh ấy **[kiểm chứng]**. Trước khi sửa, `kubectl` gọi
một địa chỉ workstation không tới được và timeout.

**A3.5** **Ý chính:** "Agent SSM *trên gateway* mở kết nối, không phải workstation. Nên gateway phải phân giải được
endpoint private — VPC cần bật DNS — và security group của cụm phải cho gateway vào cổng 443. Workstation chỉ giữ đầu
local của tunnel."

**A3.6** **Ý chính:** "Không. CI không bao giờ gọi API server: nó push image lên ECR và commit một dòng vào Git, rồi
Argo CD bên trong cụm tự kéo về. Đó cũng là lý do tôi tách CI khỏi CD ngay từ đầu."

*Nếu được hỏi thêm:* CI/CD A1.1.

**A3.7** **Ý chính:** "Key của gateway nằm trong một secret mà chỉ vai trò của chính gateway đọc được — không node,
không pod nào đọc được. Còn người vận hành thì mỗi người tự tạo cặp key của mình, giữ nửa private trên máy mình, chỉ
gửi nửa public để thêm vào gateway. Một private key đã đi qua tay người khác thì không còn là private key."

### A4. Spot

**A4.1** **Ý chính:** "Vì chi phí. Nhưng quan trọng hơn là hệ quả của nó: node có thể biến mất sau hai phút báo trước.
Tôi coi đó là một đặc tính hệ thống phải chịu được, không phải một rủi ro để giảm thiểu."

**A4.2** **Ý chính:** "App chạy ít nhất hai replica rải trên nhiều node. Phân tích canary phải phân biệt được 'bản mới
tệ hơn' với 'một node vừa biến mất giữa lúc đo'. SLO phải sống qua ngày AWS đòi lại capacity. Quyết định Spot từ stage
1 thì các stage sau được thiết kế cho nó; quyết định muộn thì stage nào cũng phải vá."

**A4.3** **Ý chính:** "Không. PDB chỉ giới hạn việc *tự nguyện* đuổi pod, như khi drain. Nó không chặn được việc
instance bị thu hồi. Thứ bảo vệ service là việc rải replica trên nhiều node; PDB chỉ đảm bảo một lần drain không làm
tệ thêm."

*Nếu được hỏi thêm:* managed node group phản ứng với tín hiệu rebalance — dựng node thay thế trước rồi mới drain node
cũ. Nếu thông báo thu hồi tới trước, việc drain chỉ là cố gắng tối đa trong hai phút **[kiểm chứng]**.

### A5. Danh tính

**A5.1** **Ý chính:** "Có sáu chủ thể gọi vào AWS, không cái nào dùng key. GitHub Actions dùng OIDC, chỉ push được
image. Mỗi controller trong cụm có liên kết Pod Identity riêng. Node dùng vai trò của nó để kéo image và cho CNI gắn
địa chỉ mạng. Dịch vụ EKS có vai trò của cụm. Gateway đọc được đúng key của nó và làm máy đích SSM. Và tôi, qua
workstation, có quyền admin — nên workstation không mở cổng vào nào. Với mỗi cái tôi hỏi: tệ nhất nó làm được gì?"

**A5.2** **Ý chính:** "Nếu không chặn metadata thì pod nào trên node cũng mượn được vai trò của node, nên một pod bị
chiếm là thừa hưởng mọi quyền của node. IRSA ràng một vai trò với đúng một ServiceAccount qua OIDC issuer của cụm. Pod
Identity làm cùng việc đó mà không cần issuer, và việc ràng buộc nằm trong một object của EKS. Tôi chọn Pod Identity
vì ít thứ để sai hơn, không phải vì IRSA không làm được."

*Nếu được hỏi thêm:* Medical dựng IRSA bằng tay — tự host issuer, một vai trò cho mỗi workload — vì kubeadm không có
issuer sẵn. Chạy tốt, nhưng có rất nhiều thứ phải tự dựng và tự giữ.

**Mẹo:** đừng nói Pod Identity "an toàn hơn" IRSA. Nói nó "ít cấu hình hơn cho cùng một mức cô lập".

**A5.3** **Ý chính:** "Tin đúng một repo *và* đúng nhánh `main`, và chỉ được push lên hai repo ECR. Nếu trust chỉ ghi
tên repo thì workflow chạy trên nhánh nào cũng thoả — kể cả nhánh không phải do người bảo trì viết. Nhánh không phải
chi tiết: nó là khác biệt giữa 'pipeline release của tôi' và 'bất cứ thứ gì chạy trong repo của tôi'."

**A5.4** **Ý chính:** "Phạm vi gọn nhất cho External Secrets là mọi secret dưới tiền tố `anime/`, và bản thiết kế đầu
của tôi viết đúng như thế. Nhưng key của gateway WireGuard cũng nằm dưới `anime/`. Một wildcard như vậy sẽ cho một
controller *bên trong* cụm đọc được key của tunnel *đi vào* cụm. Tôi sửa trước khi dựng: giới hạn tới ba secret có tên
cụ thể. Một wildcard là lời hứa về mọi cái tên mà ai đó sẽ thêm vào sau này, và không ai đọc lại policy khi thêm."

**Mẹo:** đây là một câu chuyện tốt vì nó cụ thể — một ví dụ, một lý do, một nguyên tắc rút ra.

**A5.5** **Ý chính:** "Hai lớp độc lập. external-dns được cấu hình chỉ xét các tên thuộc `anime.recruitai.io.vn`, và
danh tính AWS của nó chỉ được đổi bản ghi thuộc tên miền đó. Lớp đầu là cấu hình, có thể sai; lớp sau là quyền, vẫn
đứng vững khi cấu hình sai. Một controller có lỗi không được phép làm sập app của Medical."

*Nếu được hỏi thêm:* bản ghi TXT mà external-dns dùng để đánh dấu quyền sở hữu tên gốc có thể mang một cái tên nằm
ngoài phạm vi đó; một tiền tố cho bản ghi TXT giữ nó ở trong **[kiểm chứng]**.

**A5.6** **Ý chính:** "Pod thường thì không: IMDSv2 với hop limit 1 khiến dịch vụ metadata chỉ trả lời chính node,
không trả lời một container đứng sau nó. Nhưng pod chạy trên mạng của host thì vẫn tới được — CNI của VPC là một pod
như thế, và nó dùng vai trò của node cho quyền mạng của chính nó."

### A6. Thứ tự dựng

**A6.1** **Ý chính:** "Argo CD được cài bởi một stack có provider `helm` và `kubernetes`, mà hai provider đó phải nói
chuyện được với API server. Endpoint private tồn tại ngay khi cụm tồn tại, nhưng từ ngoài VPC không ai tới được cho
tới khi tunnel mở. Mà tunnel lại cần gateway, thứ chính lần apply đó đang tạo. Dồn vào một lần apply là kiểu bẫy kinh
điển: plan thường êm, apply chết giữa chừng, để lại một state mô tả nửa cái cụm."

**A6.2** **Ý chính:** "`make shared`, rồi `make infra` dựng cụm và gateway, rồi `make tunnel` mở tunnel qua gateway,
rồi `make bootstrap` cài Argo CD qua `127.0.0.1:6443`. Thứ tự này không phải cho gọn; nó là thứ tự duy nhất chạy
được."

### A7. Pass mà vẫn hỏng

**A7.1** **Ý chính:** "Bốn cách. `plan -refresh=false` hay đọc lại một plan đã lưu thì báo 'không thay đổi' mà không
đối chiếu resource với thực tế, nên drift vô hình. Không có số dự kiến thì 'không thay đổi' chỉ là ghi nhận, không phải
khẳng định. Plan nhầm một stack khác đã apply rồi thì nó trả lời đúng — về một thứ khác. Và `shared` với `cluster` chỉ
nói chuyện với API của AWS, nên cả hai hoàn hảo trong khi tunnel hỏng hẳn."

*Nếu được hỏi thêm:* `-refresh=false` vẫn đọc data source, nên nhìn thì tưởng nó có hỏi AWS. Còn một thư mục rỗng thì
không lừa được ai — Terraform từ chối plan khi không có cấu hình nào.

**A7.2** **Ý chính:** "Vì 'không thay đổi' chỉ nói rằng cấu hình và thực tế khớp nhau, không nói rằng cấu hình đủ.
Thiếu hẳn một phần resource thì plan vẫn êm. Đi kèm `[điền: số resource dự kiến]` thì nó thành một khẳng định có thể
sai."

**A7.3** **Ý chính:** "Khi `kubectl get --raw /readyz` in ra `ok` từ workstation, qua tunnel. Điều đó vốn nằm ngoài
tiêu chí #1, nhưng lại là thứ quan trọng nhất vào buổi sáng đầu tiên. Nó cũng là phép kiểm đầu tiên của mọi phiên làm
việc ở mọi stage sau."

*Nếu được hỏi thêm:* lần dựng đầu in ra `[điền: đầu ra của /readyz qua tunnel]`.

### A8. Giới hạn và đánh đổi

**A8.1** **Ý chính:** "Ba điểm: zone Route 53, ops workstation và bucket state đều là của Medical. Huỷ stack `shared`
của Medical thì bản ghi xác thực chứng chỉ và các tên của Anime mất cùng lúc. Tôi chấp nhận vì một domain thứ hai tốn
tiền hằng năm, và tôi ghi nó ra thành một ràng buộc đã biết thay vì để ai đó tự phát hiện."

**A8.2** **Ý chính:** "Mất mọi UI admin và mọi `kubectl` cùng một lúc — nhưng service vẫn phục vụ bình thường, vì
đường truy cập của người vận hành không nằm trên đường đi của request. Sự bất đối xứng đó là có chủ ý."

*Nếu được hỏi thêm:* dựng lại thì gateway có Elastic IP mới. Profile WireGuard gọi gateway bằng tên `vpn.anime` nên tự
theo bản ghi mới, nhưng một laptop còn cache địa chỉ cũ sẽ bắt tay thất bại cho tới khi cache hết hạn — và lỗi đó trông
như lỗi tường lửa.

**A8.3** **Ý chính:** "Tiết kiệm chi phí, đổi lại là một điểm hỏng duy nhất cho mọi thứ pod gọi ra ngoài VPC: Gemini,
Hugging Face, Langfuse, webhook Discord. Mất zone chứa NAT là mất cả bốn, và SLI ghi nhận đó như lỗi của chính service."

**A8.4** **Ý chính:** "Đúng với điều kiện bản ghi xác thực vẫn còn trong zone. Có thể còn một điều kiện nữa: chứng chỉ
phải đang được gắn vào một load balancer lúc việc gia hạn chạy. Điều đó tôi chưa kiểm với tài liệu AWS hiện tại. Trên
một cụm bị huỷ mỗi tối, có một phần mỗi ngày chứng chỉ không được gắn vào đâu. Nên tôi ghi nó thành một rủi ro chưa
kiểm, không giả định nó đúng. Kết quả thật: `[điền: gia hạn hay cấp lại]`."

**Mẹo:** "tôi chưa kiểm, và đây là điều tôi sẽ kiểm" là câu trả lời mạnh hơn một khẳng định không có căn cứ.

### A9. Nhìn lại

**A9.1** **Ý chính:** "Ba chỗ, đều phát hiện khi rà lại thiết kế, trước khi dựng. Tôi từng định để endpoint public và
giới hạn bằng Elastic IP của workstation — lập luận đúng, kết luận lười; khi đã có gateway trong VPC thì đóng hẳn được.
Bản thiết kế đầu cho External Secrets đọc `anime/*`, tức là đọc được cả key VPN. Và tôi đã ghi sai về Medical, rằng nó
không có IRSA — trong khi nó có, dựng bằng tay. Lỗi cuối dạy tôi một điều đơn giản: đọc lại nguồn, đừng viết từ trí
nhớ."

*Nếu được hỏi thêm:* mỗi stage có một mục riêng "stage này có thể pass trong khi hỏng như thế nào" — xuất phát từ bài
học ở phase CI của Medical, khi năm phép kiểm pass trong lúc thứ chúng bảo vệ đang hỏng.

**A9.2** **Ý chính:** "Những thứ tôi đã ghi là ràng buộc thì sẽ thành việc phải làm. Anime có zone và bucket state
riêng thay vì dựa vào Medical. Mỗi người có danh tính SSO riêng thay vì cùng dùng quyền admin của workstation. Và plan
chạy tự động trên pull request để ai cũng thấy thay đổi trước khi apply."

*Nếu được hỏi thêm:* các ràng buộc đó nằm trong phần rủi ro và quyết định của design; một đội năm người là lúc chúng
không còn rẻ nữa.

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)
