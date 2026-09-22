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

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Phía Medical **đã dựng và đã chạy**; phía Anime **mới thiết kế,
chưa dựng**. Câu trả lời tốt nói phía Medical bằng kinh nghiệm, phía Anime bằng thiết kế, và không trộn hai thì với nhau.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Vì sao lại có hai project, một self-managed và một managed, thay vì một?

**A1.2** Tóm tắt những chỗ hai project chọn khác nhau.

**A1.3** "Managed" rốt cuộc là chuyển cái gì sang AWS, và cái gì vẫn là của mình?

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
