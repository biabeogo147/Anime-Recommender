# Câu hỏi về Terraform

Stage này dựng tài khoản AWS từ con số không: mạng, cụm EKS, node Spot, registry, secret, chứng chỉ, và một cửa
vào không có địa chỉ nào trên internet. Bộ câu hỏi kiểm xem bạn giải thích được vì sao mọi thứ được chia theo
vòng đời, vì sao API server bị đóng hẳn thay vì giới hạn bằng danh sách IP, và stage này chứng minh được gì,
chưa chứng minh được gì.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về từng khối trong `infra/terraform/`; code đó đã có, nên phần này giờ viết được |

Bộ liên quan: [tổng quan project](../common/questions.md), [managed so với self-managed](../aws/questions.md),
[GitOps](../2-gitops/questions.md), [CI/CD](../3-cicd/questions.md). Ý tưởng của stage: [README](README.md) ·
[concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **đã dựng và đã chạy** — criterion #1 đóng
([evidence](../evidence/terraform.md)) — nên nói "tôi đã chạy" được, miễn là con số lấy từ evidence chứ không từ trí
nhớ. Câu nào bắt bạn phải mở design mới trả lời được thì đó là câu cần đọc lại.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage Terraform trong một tới hai phút.

**A1.2** Vì sao stage đầu tiên không phải là một tính năng, mà là một tài khoản dựng lại được từ con số không?

**A1.3** Tiêu chí #1 là gì, và nó chứng minh được điều gì?

**A1.4** Stage này đã chứng minh được gì, điều gì chỉ là suy luận, và điều gì vẫn là giả định?

### A2. Chia theo vòng đời

**A2.1** Vì sao không để tất cả trong một stack Terraform?

**A2.2** Thứ gì nằm trong `shared`, thứ gì nằm trong `cluster`, và câu hỏi nào quyết định một tài nguyên thuộc
bên nào?

**A2.3** Chứng chỉ ACM là ví dụ rõ nhất cho việc chia stack. Hãy giải thích vì sao.

**A2.4** Giữa `shared` và `cluster`, bên nào đọc bên nào? Vì sao chiều đó quan trọng?

**A2.5** Còn stack `bootstrap` thì sao? Nó có cái bẫy nào?

**A2.6** Medical cũng chia theo vòng đời. Anime khác ở đâu?

**A2.7** State của Terraform nằm ở đâu, và điều gì ngăn hai lần apply ghi đè lên nhau?

### A3. Một API server không có địa chỉ public

**A3.1** Cách làm phổ biến là để endpoint public rồi giới hạn bằng danh sách IP. Vì sao bạn không làm vậy?

**A3.2** Vậy `kubectl` tới API server bằng đường nào?

**A3.3** Gateway WireGuard gánh hai việc. Đó là hai việc gì, và vì sao một máy lại gánh được cả hai?

**A3.4** `tls-server-name` trong kubeconfig để làm gì? Vì sao Medical không cần nó?

**A3.5** Khi port-forward qua SSM, máy nào thực sự mở kết nối tới API server? Điều đó kéo theo những gì?

**A3.6** Đóng endpoint public thì CI có bị ảnh hưởng không?

**A3.7** Key của gateway WireGuard được giữ thế nào? Còn key của người vận hành?

### A4. Spot

**A4.1** Vì sao chọn node Spot?

**A4.2** Chọn Spot ở stage 1 ép gì lên các stage sau?

**A4.3** PodDisruptionBudget có bảo vệ service khỏi việc AWS thu hồi node Spot không?

### A5. Danh tính

**A5.1** Không có access key nào trong project. Vậy có những danh tính nào, và mỗi cái được làm gì?

**A5.2** Pod Identity, IRSA và instance role của node khác nhau thế nào? Vì sao chọn Pod Identity?

**A5.3** Trust policy của vai trò CI giới hạn tới đâu, và vì sao phải giới hạn tới nhánh chứ không chỉ tới repo?

**A5.4** Kể về lần suýt cho External Secrets quyền đọc quá rộng.

**A5.5** external-dns ghi bản ghi vào một zone của dự án khác. Bạn giới hạn nó thế nào?

**A5.6** Pod có mượn được quyền của node không?

### A6. Thứ tự dựng

**A6.1** Vì sao một lần `terraform apply` không dựng được toàn bộ?

**A6.2** Kể thứ tự bốn lệnh, và mỗi lệnh chờ gì từ lệnh trước.

### A7. Pass mà vẫn hỏng

**A7.1** Tiêu chí #1 là "apply, plan lại, không có thay đổi". Nó có thể pass trong khi hệ thống đang hỏng theo
những cách nào?

**A7.2** Vì sao phải ghi số lượng resource dự kiến *trước khi* apply?

**A7.3** Stage này chưa dùng được cho tới khi điều gì xảy ra, dù tiêu chí #1 đã pass?

### A8. Giới hạn và đánh đổi

**A8.1** Anime phụ thuộc vào Medical ở những điểm nào? Vì sao chấp nhận?

**A8.2** Mất gateway thì mất gì, và còn lại gì?

**A8.3** Một NAT gateway cho cả hai zone. Đánh đổi đó là gì?

**A8.4** "AWS tự gia hạn chứng chỉ" — câu này đúng tới đâu?

### A9. Nhìn lại

**A9.1** Khi rà lại thiết kế stage này, bạn phát hiện những lỗi nào?

**A9.2** Nếu đây là hạ tầng cho một đội năm người chứ không phải một người, bạn đổi gì?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §3](../eks-sre-llmops-design.md#3-architecture)
