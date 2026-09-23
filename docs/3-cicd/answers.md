# Đáp án CI/CD

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `GitOps A2.1` trỏ tới bộ tương ứng.

Pipeline **đã dựng và đã chạy**: criteria #3, #4, #5 đóng ngày 2026-09-22 ([evidence](../evidence/cicd.md)); riêng
thời lượng pipeline vẫn *pending*. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi dùng — đừng nói con số bạn
chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số thập phân viết bằng
dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **phép kiểm** cho một check; **gate** cho phép kiểm chặn được build;
**positive control** cho một lần chạy cố ý dựng sao cho gate đang hoạt động phải đỏ. *Negative test* là tên mà
evidence dùng cho lần cố ý làm phép kiểm index đỏ — về bản chất cũng là một positive control.

**Số liệu đã có** — đo local ở phase app ([`../evidence/local.md`](../evidence/local.md)), được phép nói:

| Số | Giá trị | Dùng ở |
|---|---|---|
| Image cũ, một image duy nhất | 6.45 GB | A7.1 |
| Image mới | api 619 MB, ui 559 MB | A7.1 |
| Mức giảm của api | −90% | A7.1 |
| Negative test của index, local | `EXPECTED_DOCS=270` → build thất bại với `IndexValidationError` | A3.2 |
| Token HF trong `docker history` và `docker save` | 0 lần | A3.7 |

**Còn phải điền:**

| Chỗ cần điền | Lấy từ | Dùng ở |
|---|---|---|
| Thời gian một lần pipeline trên `main` | Lần chạy CI đầu | A1.3 |
| Kích thước hai image do CI push | Lần chạy CI đầu | A7.1 |
| Dòng lỗi khi CSV bị cắt ngắn trong CI | Lần kiểm #5 | A3.2 |
| Kết quả positive control của Trivy, và tổng số critical so với số có bản vá | Lần chạy positive control | A3.5 |
| `hit@4` của baseline và của pull request làm giảm chất lượng | Lần kiểm #13, nếu eval gate được dựng | A7.2 |

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Pipeline này đã chạy thật, #3, #4, #5 đóng; riêng thời lượng pipeline tôi chưa đo.
GitHub Actions biến một thay đổi đã merge thành một image đã test, đã scan và đã ký. Image được push lên ECR theo
digest, rồi pipeline commit đúng một dòng — digest mới — vào Git. Nó dừng ở đó; deploy là việc của Argo CD. Hai quy
tắc chạy xuyên suốt. Mọi phép kiểm phải từng được thấy thất bại. Và chữ ký phải được verify với đúng workflow, đúng
nhánh."

*Nếu được hỏi thêm:* thứ tự là lint, unit test, hadolint và so sánh output của `sloth generate` với file đã commit →
build index và kiểm đủ 269 tài liệu → build hai image → Trivy, report SARIF lên code scanning → chỉ trên `main`: đổi
token OIDC lấy quyền AWS, push theo digest, ký và gắn SBOM, rồi commit của bot. Scan đứng trước push và ký, để không
gì chưa scan rời khỏi runner, và chữ ký mang nghĩa "đã qua gate". Digest được push có trùng với digest đã scan không
thì phải kiểm **[kiểm chứng: registry tính digest lúc push]**.

**Mẹo:** tách rõ "đã đo local" với "thiết kế cho CI". Người phỏng vấn sẽ hỏi con số, và bạn có vài con số thật.

**A1.2** **Ý chính:** "Image được build bằng tay trên một laptop. Ai build được thì ship được; không ai nói được
trong image có gì, hay nó được build từ commit nào; và một lần release là có người gõ digest vào file values rồi
hy vọng."

**A1.3** **Ý chính:** "#3: push lên `main` thành image đã ký trong ECR, và Argo CD sync — verify chữ ký theo digest.
#4: kích thước image trước và sau, cho cả hai image. #5: CI thất bại khi file dữ liệu bị cắt ngắn, với đúng dòng lỗi
của phép kiểm index. #13, là P1: một pull request làm giảm chất lượng tìm kiếm thì bị chặn."

*Nếu được hỏi thêm:* thời gian một lần pipeline `[điền: thời gian pipeline trên main]`.

### A2. CI dừng ở một commit

**A2.1** **Ý chính:** "Nếu CI chạy `kubectl` hay `helm` thì nó cần credential vào một API server không có địa chỉ
public. Và nguồn sự thật bị dời đi: cụm chạy thứ mà pipeline cuối cùng để lại, còn Git chỉ mô tả gần đúng. Với một
commit làm điểm bàn giao, Git nói cái gì *nên* chạy, quyền AWS của CI dừng ở việc push image, và rollback là revert
một dòng thay vì chạy lại một pipeline cũ."

*Nếu được hỏi thêm:* GitOps A2.1 và Terraform A5.3. Trust của vai trò CI chỉ nhận `main`, nên pull request từ chính
repo cũng không lấy được quyền push — một lớp chặn thứ hai, bên cạnh điều kiện trong workflow.

**A2.2** **Ý chính:** "Tag là một cái tên di chuyển được. Digest là hash của manifest image, nên nó ghim đúng nội
dung. Git ghi digest, Argo CD deploy digest, chữ ký nằm trên digest — cả ba luôn chỉ về cùng một image. Chen một
tag vào bất cứ đâu trong chuỗi đó thì các chỗ còn lại có thể lặng lẽ chỉ sang thứ khác, mà vẫn 'khớp'."

*Nếu được hỏi thêm:* nếu build push một index — nhiều manifest cho nhiều nền tảng hay kèm provenance — thì index có
digest riêng, và đó là digest phải dùng. buildx có thể gắn provenance mặc định, nên kể cả build một nền tảng cũng có
thể ra index **[kiểm chứng]**. cosign ký đúng digest được đưa cho nó, tức là index.

**A2.3** **Ý chính:** "Revert commit của bot, digest cũ quay lại, Argo CD deploy nó — *nếu image đó còn tồn tại*.
ECR giữ 20 image gần nhất. Nếu chữ ký và attestation được lưu thành các mục riêng và bị tính vào giới hạn đó, mỗi lần
release chiếm khoảng ba chỗ, và rollback chỉ lùi được khoảng sáu bản **[kiểm chứng]**. Rollback chỉ lùi được xa tới
mức retention cho phép, và đó là một con số phải kiểm, không phải giả định."

**A2.4** **Ý chính:** "Không. Trong lúc canary chạy, hoặc sau một lần canary bị huỷ, Git nói bản mới còn cụm chạy bản
cũ hoặc cả hai. Điều quan trọng là sự khác biệt đó *nhìn thấy được*: Argo CD hiện nó qua health của Rollout, thay vì
che đi. Hai bên được phép lệch nhau, miễn là ai cũng nhìn thấy chỗ lệch."

### A3. Mọi phép kiểm phải nói được "không"

**A3.1** **Ý chính:** "Là trường hợp thất bại của nó đã được cố ý tạo ra và nhìn thấy. Một phép kiểm chỉ từng pass
thì 'nó pass', 'nó không chạy' và 'nó không thể thất bại' trông giống hệt nhau. Dấu xanh từ một phép kiểm như vậy chỉ
cho một sự yên tâm không có căn cứ."

**Mẹo:** câu hỏi đúng về một phép kiểm không phải "nó có pass không", mà "đã có ai thấy nó thất bại chưa". Nói câu
đó ra.

**A3.2** **Ý chính:** "Local, tôi đã làm nó thất bại bằng cách đặt số tài liệu mong đợi lệch một — 270 thay vì
269 — và build dừng với `IndexValidationError`. Cách đó chứng minh phép so sánh chạy đúng. #5 làm khác: nó cắt ngắn
chính *dữ liệu*, tức là đúng cái lỗi sẽ thật sự xảy ra — một file bị cắt dở. Cách đầu chứng minh phép kiểm hoạt
động; cách sau chứng minh nó bắt được đúng lỗi cần bắt."

*Nếu được hỏi thêm:* cách cắt cũng phải chọn kỹ. Cắt còn không byte nào thì lỗi là thiếu cột, không phải
`IndexValidationError`. Cắt giữa phần tóm tắt của dòng cuối thì có thể vẫn còn đủ 269 dòng. Nên cắt phải giữ header và
bỏ nguyên dòng **[kiểm chứng]**. Dòng lỗi trong CI `[điền: dòng lỗi khi CSV bị cắt ngắn]`.

**A3.3** **Ý chính:** "Vì một lần build thất bại vì cả chục lý do không liên quan gì tới index — thiếu token, lỗi
mạng. Nếu đếm mọi thất bại là 'phép kiểm đã bắn', thì một lần mất mạng cũng được tính là bằng chứng. Đòi đúng dòng
lỗi là đòi bằng chứng về *đúng* phép kiểm đó."

**A3.4** **Ý chính:** "Không hẳn. Trivy mặc định báo cả lỗ hổng chưa có bản vá. Gate của tôi bật `--ignore-unfixed`,
nên chính *gate* bỏ qua chúng, và đó là chủ ý: chặn build vì một thứ không ai vá được sẽ dạy mọi người tắt gate đi.
Nhưng có một hệ quả. Nếu mọi lỗ hổng critical của base image đều chưa có bản vá, gate sẽ pass mọi build, chừng nào
bản vá còn chưa ra."

**A3.5** **Ý chính:** "Vì cả hai image đều build từ Debian 12. Medical đã đo trên image của nó, cũng build từ Debian
12: năm lỗ hổng critical, không cái nào có bản vá ở thời điểm đo. Trên base như vậy gate chắc chắn pass. Nên nó được
ghi là chưa chứng minh, cho tới khi có một lần positive control: hạ ngưỡng severity tới khi một lỗ hổng *có* bản vá
lọt vào phạm vi, và lần chạy đó phải đỏ."

*Nếu được hỏi thêm:* kết quả `[điền: positive control, tổng critical và số có bản vá]`. Medical sau đó chuyển base
lên Debian 13 và hết cả năm lỗ hổng đó; với Anime đó là một lựa chọn còn để ngỏ. Một cái bẫy nữa từ Medical: gate
phải là chính lệnh scan — `trivy convert`, dùng để đọc lại một report đã lưu, không có `--ignore-unfixed`.

**A3.6** **Ý chính:** "Không. Gate thất bại bất cứ khi nào con số đó lớn hơn không, nên mọi lần pass đều ghi số không —
theo định nghĩa. Một số không được ghi lại chỉ là nhắc lại việc pass, không phải bằng chứng về gate. Phải ghi *tổng*
số critical cạnh số có bản vá, để 'không có gì vá được' trông khác hẳn 'không có gì cả'."

**A3.7** **Ý chính:** "Token vào build qua secret mount của BuildKit, không qua build arg, nên nó không tự thành một
layer. Nhưng một lệnh `RUN` vẫn có thể ghi nó ra file, nên tôi đo: local, tôi tìm chuỗi token trong `docker history`
và trong output của `docker save` — không thấy lần nào."

*Nếu được hỏi thêm:* nếu `docker save` xuất layer ở dạng nén thì tìm chuỗi trong đó không chứng minh được gì
**[kiểm chứng]**. Phép đo đúng hơn là giải nén từng layer rồi mới tìm.

**Mẹo:** đây là một trong vài câu bạn trả lời được bằng số đo thật. Nói rõ là đo local.

### A4. Chữ ký phải nói ai, và từ đâu

**A4.1** **Ý chính:** "Không có khoá dài hạn nào. Workflow sinh một cặp khoá tạm trong bộ nhớ. Nó chứng minh danh
tính bằng token OIDC của GitHub, và nhận từ Sigstore một chứng chỉ chỉ sống vài phút, ràng cặp khoá đó với danh tính
đó. Chữ ký và chứng chỉ được ghi vào Rekor, một log public chỉ ghi thêm. Timestamp của log cho thấy việc ký xảy ra
khi chứng chỉ còn hiệu lực. Rồi khoá tạm bị bỏ."

**A4.2** **Ý chính:** "cosign tự kiểm chuỗi chứng chỉ tới root của Sigstore và bản ghi trong Rekor. Phần tôi phải tự
ghi là ba thứ, cộng issuer. Đúng digest mà Git ghi — không phải tag. Đúng workflow release, `ci.yml`. Và đúng nhánh
`main`. Danh tính được ghi *chính xác*, không dùng pattern, và issuer cố định là của GitHub Actions."

*Nếu được hỏi thêm:* vì không có khoá cố định để so, thứ duy nhất phân biệt chữ ký của mình với chữ ký của người
khác là danh tính trong chứng chỉ, cùng issuer đã bảo lãnh cho nó.

**A4.3** **Ý chính:** "Vì verify theo repo chấp nhận chữ ký của bất kỳ workflow nào, trên bất kỳ nhánh nào — một nhánh
tính năng, merge ref của một pull request, workflow eval. Đó đúng là lỗi mà bộ Terraform cảnh báo với trust của AWS:
nói *ở đâu* mà không nói *cái nào*. Thêm nữa, pattern của cosign là tìm chuỗi con nếu không neo, nên một pattern lỏng
chấp nhận mọi danh tính chỉ cần *chứa* tên của mình."

*Nếu được hỏi thêm:* Terraform A5.3.

**A4.4** **Ý chính:** "Rekor ghi public và vĩnh viễn: digest, repo, workflow đã ký. Image của Medical là private, và
digest của nó không có lý do gì để công khai, nên Medical ký bằng khoá KMS, không qua log. Ở Anime, repo vốn đã public,
một digest không cho ai kéo được image nếu không có quyền vào registry, và chính log là thứ cho phép bất kỳ ai verify
mà không cần khoá. Nên tôi chấp nhận, và ghi rõ đánh đổi đó."

*Nếu được hỏi thêm:* keyless so với KMS ở bộ AWS.

**A4.5** **Ý chính:** "SBOM là danh sách mọi package trong image, ở đây theo định dạng SPDX. Gắn nó vào digest như
một attestation đã ký thì khi một lỗ hổng mới được công bố, tôi đọc SBOM của từng digest — nhẹ hơn nhiều so với kéo cả
image về scan lại. Muốn tra một lần cho mọi image thì phải gom SBOM vào một kho, và thiết kế chưa có kho đó. Còn chữ
ký: ai có quyền push cũng gắn được một attestation *thứ hai* vào cùng digest. Attestation đã ký chỉ phân biệt được nếu
lúc verify cũng ghim người ký, y như khi verify image."

**A4.6** **Ý chính:** "Không. Kyverno nằm ngoài phạm vi, nên không có admission control nào từ chối image chưa ký.
Chữ ký chứng minh một image *có thể* được kiểm — #3 kiểm nó một lần, bằng tay — chứ không chứng minh mọi image *đã*
được kiểm. Medical định đóng khoảng hở đó bằng Kyverno; Anime để ngỏ nó, và ghi rõ ra."

**Mẹo:** đừng để người nghe tưởng "ký image" nghĩa là "cụm chỉ chạy image đã ký". Tự nói ra trước.

### A5. Người ghi duy nhất vào `main` không phải là người

**A5.1** **Ý chính:** "Quy tắc của `main` là chỉ thay đổi đã review và CI xanh mới vào được. Commit của bot là ngoại
lệ duy nhất của quy tắc đó, và là ngoại lệ bắt buộc — nó chạy sau CI, việc của nó là ghi vào đó. Kỷ luật ở đây là giữ
ngoại lệ đúng bằng một dòng trong ruleset, gọi tên một danh tính, thay vì nới quy tắc cho mọi người."

*Nếu được hỏi thêm:* danh tính nào thì chưa chốt — chốt khi viết ruleset.

**A5.2** **Ý chính:** "Có. Push bằng token của chính workflow thì không khởi động run mới; push bằng credential khác —
deploy key, token của app — thì có. Nếu ruleset không cho token của workflow đi qua **[kiểm chứng]**, bot phải dùng
loại credential thứ hai. Lúc đó, trong thiết kế hiện tại, `[skip ci]` là lớp duy nhất ngăn commit đó kéo theo một
vòng lặp vô tận. Nếu cho qua được, nó là lớp bảo vệ thứ hai. Trường hợp nào thì dấu đó cũng ở lại."

*Nếu được hỏi thêm:* có thể thêm một lớp nữa — workflow bỏ qua các thay đổi chỉ nằm trong `deploy/`.

### A6. Pull request từ bên ngoài

**A6.1** **Ý chính:** "Pull request từ fork không đọc được secret, mà build index cần token Hugging Face, và index nằm
*trong* image — nên nó chỉ được lint và chạy unit test, không bao giờ được build. Pull request từ chính repo thì build
và scan, nhưng không image nào rời khỏi runner; chỉ report scan được upload. Chỉ trên `main` mới push, ký, attest và
commit."

*Nếu được hỏi thêm:* cách "vòng qua" là chạy workflow ở ngữ cảnh của repo đích để có secret — nhưng như thế là đưa
secret cho code chưa ai review. Tôi không làm vậy.

**A6.2** **Ý chính:** "CI chứng minh được ít hơn nhiều về một thay đổi từ bên ngoài so với một thay đổi từ bên trong.
Người merge phải biết điều đó từ trước — một dấu xanh trên pull request từ fork không có nghĩa là image đã được build
hay scan."

### A7. Kích thước image và eval gate

**A7.1** **Ý chính:** "Local, image cũ là một image duy nhất 6.45 GB, vì nó kéo cả PyTorch qua một dependency không
dùng tới. Sau khi tách và build nhiều tầng: api 619 MB, ui 559 MB. CI phải đo lại chính hai image nó push, và nói cả
*hai* so với một image cũ mà chúng thay thế."

*Nếu được hỏi thêm:* kích thước trong CI `[điền: kích thước hai image do CI push]`. Chỉ nói con số của API — mức giảm
90% — là đúng cái pass sai mà tiêu chí này cảnh báo: so một image với hai. Cũng phải so cùng một phương pháp: CI đo
bằng `docker image ls` trên runner, không lấy kích thước trong ECR, vì ECR báo kích thước nén.

**A7.2** **Ý chính:** "Chất lượng tìm kiếm, không phải tính đúng: 20 câu hỏi với tiêu đề mong đợi, tính `hit@4`, và
chặn pull request nếu điểm tụt dưới baseline. Nó không gọi model nào, nhưng vẫn phải embed câu hỏi qua API của Hugging
Face, nên cần token, có thể bị giới hạn tốc độ, và bị bỏ qua với pull request từ fork. Nó là P1 vì pipeline chính đứng
được mà không cần nó — và có thể nó sẽ không được dựng."

*Nếu được hỏi thêm:* với 20 câu, trượt một câu là `hit@4` tụt 0.05. Muốn nó thật sự chặn, nó phải là một required
check trong ruleset **[kiểm chứng: một required check chỉ chạy theo đường dẫn thì pull request không chạm tới đường dẫn
đó có bị kẹt chờ không]**. Kết quả `[điền: hit@4 của baseline và của pull request làm giảm chất lượng]`.

**A7.3** **Ý chính:** "Nếu một pull request sinh lại baseline cùng với thay đổi của nó, thì nó đang so thay đổi với
chính nó, và luôn pass. Commit của baseline phải có trước base của pull request."

### A8. Pass mà vẫn hỏng

**A8.1** **Ý chính:** "Ba cách. 'Synced' nghĩa là khớp với revision Argo CD *đang có*, và một repo-server không tới được
GitHub sẽ giữ revision cũ mãi — nên phải so revision của nó với `origin/main`. Verify theo tag thay vì theo digest ghi
trong Git thì verify một image khác với image đang chạy. Và một pattern danh tính chấp nhận mọi workflow hay mọi ref
thì pass với chữ ký từ một nhánh tính năng."

**A8.2** **Ý chính:** "Một kết quả xanh mà không nói nó xanh về cái gì — digest nào, revision nào, dòng lỗi nào,
baseline nào, workflow nào. Cách sửa lần nào cũng giống nhau: bắt bản ghi phải gọi tên thứ đó."

**Mẹo:** câu này nối thẳng với GitOps A7.4. Hai stage, cùng một kỷ luật.

**A8.3** **Ý chính:** "Khi các tiêu chí chạy xong, stage này sẽ chứng minh: một thay đổi đã merge thành image đã ký và
một commit một dòng mà không ai phải đụng tay; phép kiểm index bắt được một file bị cắt ngắn; chữ ký verify đúng với
workflow này, trên nhánh này. Nó vẫn giả định: gate scan có thể thất bại, cho tới khi positive control chạy; một image
đã ký là image an toàn, điều mà không gì thực thi; và image để rollback vẫn còn trong registry."

### A9. Giới hạn và nhìn lại

**A9.1** **Ý chính:** "GitHub Actions; ECR và STS qua OIDC; API của Hugging Face, vì build index cần nó — Hugging Face
sập thì `main` cũng không ship được; registry của base image; và Sigstore. Sigstore không dùng được thì bước ký thất
bại. Đó là cái giá của việc không giữ khoá nào: không có khoá để mất, nhưng có thêm dịch vụ bên ngoài phải chờ."

**A9.2** **Ý chính:** "Verify chữ ký ở admission, để 'đã ký' trở thành 'chỉ chạy image đã ký' — đó là khoảng hở lớn nhất
tôi đã ghi ra. Sau đó là chạy positive control của Trivy như một job định kỳ thay vì một lần, và chốt danh tính của bot
trong ruleset."

*Nếu được hỏi thêm:* stage này cũng gỡ submodule `MLops-Common`, khi không còn gì trong CI gọi các script on-premises
nằm trong đó.

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md)
