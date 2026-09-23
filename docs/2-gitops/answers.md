# Đáp án GitOps

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Terraform A5.4` trỏ tới bộ tương ứng.

Stage này **đã dựng và đã chạy trên cụm, nhưng chưa viết evidence**: cây Argo CD đã lên 8/8, HTTPS và bốn UI nội bộ
đã kiểm, song `docs/evidence/gitops.md` chưa tồn tại — nên criteria #2, #15, #16 vẫn tính là **chưa có bằng chứng**.
Kể được bằng kinh nghiệm, nhưng đừng đọc ra con số nào chưa ghi. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **cửa** cho một load balancer (cửa public, cửa nội bộ); **phép kiểm** cho
một check; **nửa âm / nửa dương** cho hai nửa của #16 (tắt VPN phải thất bại / bật VPN phải thành công).

**Số liệu đã có:** chưa có số nào cho stage này. Số đo duy nhất của project là của phase app, chạy local
([`../evidence/local.md`](../evidence/local.md)).

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| Danh sách Application theo tên, và số lượng, khi stage này đóng | Lần dựng đầu | A1.3, A7.1 |
| Serial của chứng chỉ trên listener so với chứng chỉ ACM | Lần kiểm #15 đầu | A7.2 |
| Mạng nhà có chặn câu trả lời mang địa chỉ private không | Lần kiểm #16 đầu, từ laptop | A6.2 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi đã dựng và chạy trên cụm, nhưng chưa viết file bằng chứng. Sau bootstrap không có gì được apply bằng tay: mọi
thành phần là một Application trong Git, và Argo CD trong cụm tự kéo về. Stage này đưa vào bốn thứ, theo một thứ
tự mà chính cụm phải tự giữ được: controller dựng load balancer, External Secrets, external-dns, và các UI quản
trị. Kết quả là hai cửa — một ALB public cho app, một ALB nội bộ cho bốn UI chỉ mở qua VPN. Cả hai dùng chung một
chứng chỉ ACM, và TLS kết thúc ngay ở load balancer."

*Nếu được hỏi thêm:* thứ tự ở A2.4, hai cửa ở A3.1, vì sao mỗi phép kiểm cần một phép kiểm đi kèm ở A7.4.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Nói rõ một lần là "thiết kế, chưa dựng", rồi trình bày tự nhiên.

**A1.2** **Ý chính:** "Bốn thứ. Không traffic nào vào được, vì Ingress cần một controller để thành load balancer.
Không secret nào đọc được, vì chưa có gì trong cụm đọc từ Secrets Manager. Không có tên nào, vì chưa có load
balancer nào để trỏ vào. Và không UI nào mở được từ trình duyệt. Từ workstation thì port-forward được, còn từ bất
cứ đâu khác thì không gì chạy."

**A1.3** **Ý chính:** "#2: mọi Application Synced và Healthy — kiểm theo danh sách tên, không phải theo câu 'tất
cả đều xanh'. #15: cả `anime` lẫn `api.anime` đều trả 301 ở cổng 80, trả 200 qua HTTPS với chuỗi chứng chỉ xác
thực được, và đúng là chứng chỉ ACM của mình. #16: bốn tên UI, từ laptop — tắt VPN thì không tới được, bật VPN thì
200."

*Nếu được hỏi thêm:* khi stage đóng, danh sách là `[điền: danh sách Application và số lượng]`.

### A2. Git là lối vào duy nhất

**A2.1** **Ý chính:** "Push là pipeline bên ngoài giữ credential và tự apply vào cụm. Pull là một controller
trong cụm đọc Git rồi làm cụm khớp theo. Ở đây API server không có địa chỉ public, nên nếu push thì CI phải có một
đường vào cụm. Với pull, CI chỉ cần commit, và không có gì bên ngoài cần quyền vào cụm."

*Nếu được hỏi thêm:* còn một lợi ích nữa — "cái gì đang chạy" trả lời được bằng cách đọc Git, và sau mỗi lần
teardown, cụm tự quay về đúng trạng thái đó.

**A2.2** **Ý chính:** "Một Application gốc, việc duy nhất của nó là tạo ra các Application khác. Bootstrap chỉ
cài Argo CD và cái gốc đó. Từ đó, thêm một thành phần là thêm một file vào thư mục mà cái gốc đang theo dõi."

**A2.3** **Ý chính:** "CRD dạy cho Kubernetes một loại object mới — Rollout, ScaledObject, ExternalSecret. Khi
CRD chưa có, API server từ chối mọi object loại đó. 'no matches for kind' nghĩa là object tới trước CRD của nó.
Lỗi này thường tự hết ở lần retry sau, nếu Application có bật retry **[kiểm chứng]** — và chính vì thế nó sống
sót: một lần dựng *thường* hội tụ được sẽ che mất lỗi thứ tự cho tới ngày hết lượt retry."

**A2.4** **Ý chính:** "Sync wave là một con số trên object. Trong một lần sync, Argo CD apply wave thấp trước và
chờ wave đó healthy rồi mới sang wave sau. Nhưng ở đây wave nằm trên các Application con, và Argo CD không có
sẵn health check cho kiểu Application. Không có check đó thì con nào cũng healthy ngay lúc vừa được tạo, mọi
wave chạy cùng lúc, và các con số chỉ còn là trang trí. Nên bootstrap thêm một health check cho Application. Và
check đó phải đòi cả Healthy lẫn Synced, vì Argo CD không tính resource chưa tồn tại vào health — một Application
mới apply được nửa manifest vẫn báo Healthy."

*Nếu được hỏi thêm:* không có gì báo lỗi, vì không object riêng lẻ nào sai. Cụm vẫn hội tụ nhờ retry, nên thứ
tự trên giấy trông như đang được giữ.

**Mẹo:** câu "các con số chỉ còn là trang trí" dễ nhớ. Vế Synced là chỗ phân biệt người đã đọc kỹ với người chỉ
biết có health check; câu chuyện đằng sau nó ở A9.1.

**A2.5** **Ý chính:** "Không. Một rule trên metric chưa tồn tại vẫn được chấp nhận, chỉ là không sinh ra series
nào. Wave đó chỉ để đọc cho thuận thứ tự, và tôi ghi rõ như vậy trong design để sau này không ai bảo vệ nó như
một phụ thuộc thật."

**A2.6** **Ý chính:** "Thưa hơn. Thành phần vào Git ở đúng stage cần nó: tới stage 5 thì API vẫn là một
Deployment thường, tới stage 7 mới có ScaledObject. Nên ở stage này, một số wave còn ít thứ hơn. Thứ tự vẫn giữ
nguyên."

### A3. Một controller, hai cửa

**A3.1** **Ý chính:** "Mặc định mỗi Ingress thành một ALB. Nhưng các Ingress cùng khai một group name thì được
gộp vào một ALB, kể cả khi ở khác namespace. Bốn UI quản trị nằm ở bốn namespace, mà một Ingress chỉ trỏ được tới
Service trong namespace của nó. Nên mỗi UI có một Ingress riêng, cả bốn cùng một group, thành một ALB nội bộ. Cộng
một Ingress public cho app: năm object, hai load balancer."

**A3.2** **Ý chính:** "Load balancer do controller tạo, Terraform không biết chúng tồn tại, và VPC không huỷ
được khi chúng còn đó. Nếu teardown chỉ xoá 'hai Ingress' thì ALB nội bộ vẫn đứng đó, và việc huỷ VPC bị kẹt.
Phải xoá cả năm Ingress và chờ controller dọn xong hai load balancer."

**A3.3** **Ý chính:** "Vì nó dựng cả hai cửa, và từ stage 5 nó còn là thứ *thực thi* việc chia traffic giữa bản
stable và bản canary: Argo Rollouts quyết định trọng số, controller ghi trọng số đó vào listener. Controller này
không khoẻ thì người dùng không vào được app, *và* không bản release nào tiến lên được. Nó là single point of
failure — hỏng một chỗ này là mất cả truy cập lẫn release — và tôi ghi rõ điều đó trong design."

**A3.4** **Ý chính:** "Đăng ký bằng IP thì mỗi pod là một target, load balancer gửi thẳng tới pod. Đăng ký bằng
node thì request đi qua node port, và node port có thể chuyển tiếp sang một pod ở node khác — kể cả một pod của
bản kia, nếu selector của Service phủ cả hai bản. Readiness gate chỉ có nghĩa khi target là pod. Và Argo Rollouts
kiểm lại trọng số trên target group có đúng như nó yêu cầu không — việc đó cũng cần target là IP."

*Nếu được hỏi thêm:* bản thân việc chia traffic vẫn chạy được với target là node — hai Service với selector khác
nhau vẫn ra hai node port. Cái mất là đường đi thẳng, không phải khả năng chia.

**A3.5** **Ý chính:** "Khi mọi target trong một nhóm đều trượt health check, ALB vẫn gửi traffic tới tất cả —
đó là fail open. Nên một đường dẫn health check sai là vô hình: người dùng vẫn được phục vụ, không gì báo động, và
'healthy' không còn nghĩa gì. Với readiness gate, pod chỉ Ready khi load balancer coi target của nó là healthy.
Cùng lỗi đó giờ khiến pod mới không Ready, và rollout dừng lại thay vì âm thầm chạy tiếp. Lỗi vẫn là một;
readiness gate đổi nó từ im lặng thành ồn ào."

*Nếu được hỏi thêm:* health check mặc định gọi `GET /`, đường dẫn mà cả hai app đều không phục vụ, nên mỗi app
khai rõ đường dẫn của mình — `/healthz` cho API, `/_stcore/health` cho UI. Gate chỉ được gắn vào pod tạo ra sau
khi target group binding đã tồn tại, nên những pod đầu tiên của lần dựng đầu có thể lọt qua **[kiểm chứng]**.

**Mẹo:** đây là câu thể hiện rõ nhất cách nghĩ của cả project — "khi một cấu hình sai là có thể xảy ra, hãy làm
cho nó ồn ào". Nói câu đó ra.

**A3.6** **Ý chính:** "Ở load balancer. Đó là hệ quả của việc chọn ACM, không phải ngược lại. Tôi chọn ACM vì AWS
tự gia hạn và không có gì phải sao lưu rồi khôi phục mỗi lần dựng lại — mà chứng chỉ ACM loại thường chỉ gắn được
vào load balancer và các dịch vụ tích hợp khác của AWS, vì private key không ra khỏi ACM **[kiểm chứng: ACM nay
có loại chứng chỉ public export được, có phí]**. Nên phía sau nó, trong VPC, là HTTP thường, và không cần ingress
controller thứ hai. Cổng 80 của cửa public chỉ để trả về lệnh chuyển hướng."

*Nếu được hỏi thêm:* muốn kết thúc TLS trong cụm thì phải đổi cửa trước — NLB cộng một ingress controller — và kéo
theo đúng việc sao lưu chứng chỉ mà ACM được chọn để tránh. So sánh ACM với Let's Encrypt nằm ở bộ AWS.

**A3.7** **Ý chính:** "Vì nếu không ghi, controller tự chọn chứng chỉ bằng cách khớp host của Ingress với mọi
chứng chỉ ACM trong tài khoản. Một tài khoản dùng chung cho nhiều dự án có thể giữ một chứng chỉ khác cũng khớp
host, nên nó có thể chọn trúng một cái không ai định — mà chuỗi chứng chỉ vẫn xác thực được. Phép kiểm 'chứng chỉ
hợp lệ' sẽ pass, về một chứng chỉ khác."

**A3.8** **Ý chính:** "Việc chia canary là một action forward có trọng số, gắn vào listener rule của cửa public.
API cần một rule riêng để gắn action đó, và một host riêng cho nó rule ấy mà không đụng tới rule của UI. Thêm nữa,
k6 cần gọi thẳng vào API."

**A3.9** **Ý chính:** "Tag của subnet. Controller tìm subnet bằng tag: một tag đánh dấu subnet public cho cửa
internet-facing, một tag khác đánh dấu subnet private cho cửa nội bộ. Thiếu một tag thì đúng một loại cửa hỏng, còn
loại kia vẫn chạy — nhìn thì giống lỗi của Ingress, nhưng thật ra là lỗi của mạng. Chỗ để đọc là event của Ingress
và log của controller, không phải manifest."

**A3.10** **Ý chính:** "Chứng chỉ ACM còn chờ xác thực. Nếu bản ghi xác thực không có trong zone, chứng chỉ không
bao giờ được cấp, và không có listener HTTPS nào gắn được nó — trong khi Ingress trông hoàn toàn bình thường. Bản ghi
đó do stack `shared` viết, nên đây là một lỗi của stage 1 lộ ra ở stage 2."

### A4. Secret

**A4.1** **Ý chính:** "Nó đọc giá trị từ Secrets Manager rồi ghi thành Secret trong Kubernetes. Git chỉ giữ
ExternalSecret — tên secret cần lấy và tên Secret đích — không bao giờ giữ giá trị. Nó xác thực bằng danh tính
riêng qua Pod Identity, và chỉ được đọc đúng ba secret có tên."

*Nếu được hỏi thêm:* vì sao là ba tên chứ không phải `anime/*` — ở Terraform A5.4.

**A4.2** **Ý chính:** "Bản thân secret phải được tạo trong Secrets Manager trước. Rồi hai thay đổi ở hai nơi: một
dòng policy của External Secrets trong Terraform, và một ExternalSecret trong Git. Quên dòng policy thì
ExternalSecret báo lỗi không có quyền — hỏng ồn ào, không phải thành công lặng lẽ. Hỏng theo hướng này là an toàn:
secret mới không đọc được cho tới khi có người quyết định nó được đọc."

### A5. Tên miền

**A5.1** **Ý chính:** "Bản ghi cho load balancer là alias, và alias cần địa chỉ của đích ngay lúc được viết.
Load balancer chỉ tồn tại sau khi controller dựng chúng từ Ingress — mà Terraform chạy trước và không bao giờ thấy
Ingress nào. Nên external-dns theo dõi chính các Ingress đó và viết bản ghi cho từng host khi load balancer đã có."

*Nếu được hỏi thêm:* không có nó thì mỗi lần dựng lại phải thêm một bước tay, hoặc bản ghi sẽ trỏ vào load
balancer của hôm qua.

**A5.2** **Ý chính:** "Hai lớp độc lập: một bộ lọc trong cấu hình, và một danh tính chỉ được đổi bản ghi thuộc
`anime.recruitai.io.vn` — cách giới hạn này nằm ở Terraform A5.5. Điều stage này thêm vào là cách external-dns biết
bản ghi nào của mình: nó chỉ sửa những bản ghi có một bản ghi TXT sở hữu đi kèm, nên nó không đụng vào bản ghi của
Medical dù cùng zone."

*Nếu được hỏi thêm:* riêng bản ghi TXT sở hữu của chính tên gốc `anime` có thể mang một cái tên nằm ngoài phạm vi
policy; một tiền tố cho bản ghi TXT giữ nó ở trong **[kiểm chứng]**.

### A6. UI quản trị

**A6.1** **Ý chính:** "Tên nằm trong zone public, trỏ về ALB nội bộ. Ai cũng phân giải được, nhưng không ai tới
được địa chỉ đó nếu không có VPN — tunnel mới là thứ cấp quyền, không phải cái tên. Một private zone chỉ trả lời
client dùng resolver của VPC, tức là mọi profile VPN phải kèm một cấu hình DNS và giữ nó đúng mãi. Bản ghi public
thì miễn phí và không cần gì thêm ở laptop."

**A6.2** **Ý chính:** "Có. Nhiều router nhà chặn câu trả lời DNS public mang địa chỉ private, để chống một kiểu tấn
công gọi là DNS rebinding. Trên mạng như vậy, cái tên đơn giản là không phân giải được, bật VPN hay không cũng thế —
và nửa dương của #16 thất bại vì một lý do không liên quan gì tới cụm. Tôi ghi đó là một giả định, không phải một
điều đã chứng minh."

*Nếu được hỏi thêm:* cách vòng qua là đưa một DNS server vào profile WireGuard, hoặc dùng mạng khác — tức là đúng
cái giá mà bản ghi public được chọn để tránh. Mạng nhà của tôi `[điền: có chặn hay không]`.

**A6.3** **Ý chính:** "Hai chỗ. Gateway không bật IP forwarding thì gói từ tunnel bị bỏ ngay ở gateway, không tới
được VPC. Có forwarding mà không có masquerade — viết lại địa chỉ nguồn thành địa chỉ của gateway — thì request tới
được ALB nội bộ, nhưng câu trả lời không có đường về dải địa chỉ của client. Nhìn từ trình duyệt, cả hai đều giống
app đang chết."

*Nếu được hỏi thêm:* trước cả gateway, "bật" VPN không có nghĩa là handshake đã xong — WireGuard không có trạng
thái kết nối. Sau một lần dựng lại, laptop có thể còn giữ Elastic IP cũ của `vpn.anime` cho tới khi cache hết hạn.
Profile chỉ route dải VPC qua tunnel, nên duyệt web bình thường không đi qua VPN.

**A6.4** **Ý chính:** "Vì web app dựng link và redirect từ cái tên và scheme mà nó nghĩ mình đang được phục vụ. Sau
một load balancer đã kết thúc TLS, app chỉ thấy HTTP thường từ một địa chỉ nội bộ. Không được báo tên thật thì nó
tạo vòng lặp redirect, link về `localhost`, đăng nhập xong quay về sai trang. Mỗi UI có một thiết lập riêng cho việc
này. Argo CD còn phải được bảo thôi tự chuyển HTTP sang HTTPS, vì load balancer đã làm rồi."

*Nếu được hỏi thêm:* với Argo CD là `url` và chế độ insecure của server, với Grafana là root URL, với Prometheus
và Alertmanager là cờ external URL. Lỗi này không bao giờ lộ qua port-forward, chỉ lộ vào ngày UI có hostname.

**A6.5** **Ý chính:** "Vì ba trong bốn UI quản trị đến từ kube-prometheus-stack, mà #16 nói về cả bốn. Cách khác là
đóng #16 với một UI rồi mở lại sau — tức là một tiêu chí chỉ đúng một phần vào ngày được đánh dấu xong. Tôi chọn
đưa monitoring vào sớm hai stage."

**A6.6** **Ý chính:** "Không. Ingress cho argocd-server chỉ là một manifest thường, Argo CD sync nó như mọi thứ
khác. Việc Argo CD có tự nâng cấp chính nó từ Git sau bootstrap hay không, như Medical làm, vẫn còn để ngỏ trong
design — nhưng nó không còn quyết định ai sở hữu tên của UI nữa."

### A7. Pass mà vẫn hỏng

**A7.1** **Ý chính:** "Ba cách. Với những kiểu object Argo CD không có health check — AnalysisTemplate, PodMonitor,
PrometheusRule — nó không đánh giá chúng, nên chúng không bao giờ kéo Application khỏi Healthy, kể cả khi chúng
không làm gì. 'Synced' chỉ nghĩa là khớp với revision
Argo CD đã *tải về*, có thể chậm hơn `main`. Và 'tất cả đều healthy' cũng đúng với một danh sách rỗng. Nên phép kiểm
gọi đúng tên từng Application, đếm số lượng, so revision với `main`, và đọc một trường readiness thật cho mỗi kiểu
custom."

*Nếu được hỏi thêm:* danh sách khi stage đóng là `[điền: danh sách Application và số lượng]`.

**A7.2** **Ý chính:** "Bốn cách. Kiểm bằng `-k`, hoặc kiểm vào tên `*.elb.amazonaws.com` của ALB, nơi sai tên là
chuyện dự kiến và không nói lên gì. Chuỗi chứng chỉ xác thực được ngay cả khi app phía sau trả 404 hay 503 — TLS vẫn hoàn tất
dù không rule nào khớp hay không target group nào healthy, nên phải kiểm mã trạng thái cạnh chuỗi chứng chỉ. Một
chứng chỉ ACM khác, như ở A3.7. Và kiểm một tên trong khi tuyên bố hai. Nên phép kiểm so serial của chứng chỉ đang
được phục vụ với chứng chỉ ACM, đọc lại từ listener."

*Nếu được hỏi thêm:* kết quả so serial `[điền: serial trên listener so với ACM]`.

**A7.3** **Ý chính:** "Vì timeout cũng là hình dạng của một load balancer chưa bao giờ được dựng. Nếu Ingress nội
bộ không có load balancer nào, nửa âm pass y hệt. Nên hai nửa phải chạy trong cùng một phiên, trên cả bốn tên:
tắt VPN thì mỗi tên vẫn phân giải ra địa chỉ private nhưng không tới được, bật VPN thì 200 với chuỗi chứng chỉ
xác thực được. Cộng thêm `Scheme: internal` trên load balancer."

*Nếu được hỏi thêm:* một laptop trên mạng nhà dùng dải `10.0.0.0/8` có thể nhận `connection refused` từ chính mạng
LAN thay vì timeout. Đó là cấu hình đúng làm trượt một phép kiểm viết tồi — phép kiểm nên nói "không tới được",
không nói "phải timeout".

**A7.4** **Ý chính:** "Mỗi phép kiểm nhìn vào một dấu hiệu mà chính cái lỗi nó muốn bắt cũng tạo ra được.
'Healthy' cũng là thứ Argo CD báo khi có những object nó không đánh giá được. 'Chuỗi chứng chỉ xác thực được' cũng
đúng khi app phía sau trả 503.
'Timeout khi tắt VPN' cũng là hình dạng của một load balancer chưa từng tồn tại. Cách chống giống nhau: ghép mỗi
phép kiểm với một phép kiểm mà lỗi đó *không thể* tạo ra — tên và số lượng, mã trạng thái và serial, nửa dương
chạy cùng phiên."

**Mẹo:** nếu chỉ kịp nói một ý của stage này, nói ý này. Nó lặp lại ở mọi stage sau.

**A7.5** **Ý chính:** "Vì chỉ laptop là peer của VPN. Workstation nằm ở một VPC khác, nên nó không tới được mặt
private của cửa nào cả — từ đó thì không tới được là chuyện đương nhiên, không chứng minh được gì."

### A8. Giới hạn và đánh đổi

**A8.1** **Ý chính:** "Ai ở trên VPN, và bất cứ pod nào trong VPC, đều đọc được mọi metric và tắt được mọi cảnh
báo. Với một người vận hành, tôi chấp nhận và ghi rõ ra. Với một đội thì không. #16 chỉ chứng minh 'chỉ tới được
qua VPN', không chứng minh 'chỉ người được phép mới dùng được'."

**A8.2** **Ý chính:** "Chứng minh: mọi Application sync, kiểm theo tên; app trả lời qua HTTPS trên cả hai tên với
đúng chứng chỉ; bốn tên UI trả lời qua VPN và không tới được khi không có VPN. Giả định: mạng mà laptop đang dùng
chịu trả về địa chỉ private cho một tên public."

**A8.3** **Ý chính:** "Cửa public nhận 80 và 443 từ mọi nơi. Cửa nội bộ nhận 443 từ dải client VPN và từ dải VPC.
Phép kiểm hành vi không thấy được các rule này, vì địa chỉ private vốn không route được từ internet — tắt VPN thì
không tới được, dù rule viết thế nào. Nên các rule là một phép đọc cấu hình riêng, đối chiếu với bảng trong design,
không phải thứ suy ra từ phép kiểm #16."

*Nếu được hỏi thêm:* vì gateway masquerade, ALB nội bộ thấy nguồn là địa chỉ của gateway trong VPC, nên rule cho
dải client VPN có lẽ không bao giờ là rule khớp — rule cho dải VPC mới là rule thật sự cho qua **[kiểm chứng]**.
Đọc rule làm bằng chứng thì phải biết điều đó.

### A9. Nhìn lại

**A9.1** **Ý chính:** "Health check cho Application. Medical đã có check đó, nhưng bản đầu chỉ đọc health. Vì Argo
CD không tính resource chưa tồn tại vào health, mọi Application con báo Healthy ngay khi vừa tạo, và trong một lần
dựng lại thật, root thả hết các wave cùng lúc. cert-manager xin một chứng chỉ mới trước khi bản khôi phục kịp có
mặt, và tốn một lượt cấp của Let's Encrypt. Check đã sửa đòi cả Healthy lẫn Synced, truyền Degraded lên, và coi một
Application không có resource nào là lỗi. Tôi đưa đúng bản đã sửa đó vào bootstrap của Anime, trước khi có bất kỳ
wave nào."

*Nếu được hỏi thêm:* bài học rộng hơn — một phép kiểm pass không có nghĩa là thứ nó canh đang chạy — là lý do mỗi
stage có một mục "có thể pass mà vẫn hỏng thế nào".

**A9.2** **Ý chính:** "Đăng nhập cho Prometheus và Alertmanager, hoặc đưa chúng ra sau một lớp xác thực — đó là
giới hạn tôi đã ghi rõ là chỉ chấp nhận được với một người. Sau đó là giảm việc controller load balancer là điểm
hỏng duy nhất cho cả truy cập lẫn release, và chốt câu hỏi Argo CD có tự quản lý chính nó không."

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)
