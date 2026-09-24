# Câu hỏi về AWS: managed so với self-managed

Hai project cố ý chia đôi một chủ đề. Medical tự dựng Kubernetes bằng kubeadm trên EC2; Anime dùng EKS và các dịch vụ
managed. Bộ câu hỏi này không hỏi lại từng stage — nó hỏi về **ranh giới**: ở mỗi chỗ hai project chọn khác nhau, bạn
giải thích được mình nhận gì, trả gì, và mất khả năng làm gì.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn so sánh được hai cách làm ở từng chỗ, bằng lý do chứ không bằng sở thích |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về API và giới hạn cụ thể của từng dịch vụ, khi code của Anime đã có |

Bộ liên quan: [tổng quan project](../common/questions.md), [Terraform](../1-terraform/questions.md),
[GitOps](../2-gitops/questions.md), [CI/CD](../3-cicd/questions.md), [Scaling](../7-scaling/questions.md). Bộ AWS của
Medical: `Medical-RAG-Chatbot/docs/aws/questions.md`. Câu nào trùng với một bộ stage thì ở đây chỉ trả lời ở mức ranh
giới và trỏ sang bộ đó.

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. **Cả hai project đã dựng và đã chạy.** Anime đi hết tám
stage trong hai ngày 22–23/09/2026: **mười một** tiêu chí đóng bằng số đo trích dẫn được, ba tiêu chí nữa (#2, #15, #16) pass nhưng không giữ output, #7 đo được một nửa, #13 — cổng eval chất lượng,
hạng P1 — chưa làm. Câu trả lời tốt so hai project theo *gánh vận hành* chứ không theo danh sách tính năng, và nói
đúng ba chỗ chưa trọn thay vì nói "xong hết". Trạng thái từng criterion đọc ở
[`docs/evidence/`](../evidence/), không đọc ở câu này.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Vì sao lại có hai project, một self-managed và một managed, thay vì một?

**A1.2** Tóm tắt những chỗ hai project chọn khác nhau.

**A1.3** "Managed" rốt cuộc là chuyển cái gì sang AWS, và cái gì vẫn là của mình?

**A1.4** Câu hỏi nào chỉ Medical trả lời được, còn Anime thì không?

**A1.5** Câu hỏi nào chỉ Anime trả lời được, còn Medical thì không?

**A1.6** Có chuyện gì mà cả hai project đều không chứng minh được không?

### A2. Control plane: kubeadm so với EKS

**A2.1** Với kubeadm, bạn phải tự lo những gì mà EKS lo thay?

**A2.2** Dùng EKS thì mất những gì?

**A2.3** Cái mất đó chạm vào thiết kế của Anime ở chỗ nào cụ thể?

**A2.4** Nâng cấp phiên bản Kubernetes khác nhau thế nào giữa hai bên?

**A2.5** Khi nào bạn chọn tự dựng thay vì EKS?

**A2.6** Chi phí hai bên so với nhau thế nào?

### A3. Danh tính của pod

**A3.1** Ở một cụm tự dựng, pod lấy quyền AWS bằng cách nào? Medical làm gì?

**A3.2** Anime dùng Pod Identity. Nó khác IRSA tự dựng ở đâu?

**A3.3** "Pod Identity an toàn hơn IRSA" — câu này đúng không?

### A4. Ký image: keyless so với KMS

**A4.1** Medical ký bằng khoá KMS, Anime ký keyless. Mỗi bên giữ gì, và tin vào ai?

**A4.2** Vì sao Medical không ký keyless luôn?

**A4.3** Nếu phải chọn một cho cả hai project, bạn chọn gì?

### A5. Chứng chỉ: ACM so với Let's Encrypt

**A5.1** Medical dùng cert-manager với Let's Encrypt, Anime dùng ACM. Khác nhau về việc phải vận hành ở đâu?

**A5.2** Vì sao Anime không dùng cert-manager như Medical?

**A5.3** ACM có mặt trái nào?

### A6. CI, node, mạng và dữ liệu

**A6.1** Medical chạy Jenkins trong cụm, Anime dùng GitHub Actions. Đánh đổi là gì?

**A6.2** Medical dùng instance on-demand thường, Anime dùng Spot trong managed node group. Vì sao khác nhau?

**A6.3** Mạng và load balancer khác nhau thế nào giữa hai bên?

**A6.4** Secret trong Kubernetes được bảo vệ lúc lưu thế nào ở mỗi bên?

### A7. Vẫn là của mình

**A7.1** Những thứ nào hai project làm *giống* nhau, vì managed hay không cũng không thay đổi được?

**A7.2** Hai project dính nhau ở đâu?

### A8. Nhìn lại

**A8.1** Dựng một bên và thiết kế bên kia, bạn học được gì về "managed"?

**A8.2** Nếu một công ty hỏi nên chọn cách nào, bạn trả lời thế nào?

**A8.3** Phần nào của Anime gắn chặt với AWS, phần nào mang đi được?

---

[Đáp án](answers.md) · [Design, bảng so sánh](../eks-sre-llmops-design.md#1-goal)

---

### A10. Câu đào sâu — chi phí và bán kính ảnh hưởng

**A10.1** Chạy cái này tốn bao nhiêu?

**A10.2** Cùng một account AWS với project kia, và Anime còn ghi vào zone Route 53 của Medical. Bán kính ảnh hưởng là gì?
