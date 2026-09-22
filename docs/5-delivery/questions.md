# Câu hỏi về Progressive delivery

Stage này cho một bản mới nhận một phần traffic thật, hỏi Prometheus xem nó có tệ hơn bản cũ không, rồi mở rộng phần
đó, rollback, hoặc dừng lại chờ người. Bộ câu hỏi kiểm xem bạn giải thích được vì sao gate so với bản cũ chứ không so
với T, làm sao biết con số đang đọc là của canary, vì sao ngưỡng trên giấy chưa chắc là ngưỡng thật, và vì sao quá ít
bằng chứng thì phải dừng chứ không được promote.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về Rollout, AnalysisTemplate và từng query, và chỉ viết được khi code đã có |

Bộ liên quan: [tổng quan project](../common/questions.md), [Load](../4-load/questions.md),
[GitOps](../2-gitops/questions.md), [CI/CD](../3-cicd/questions.md), [scaling](../7-scaling/questions.md). Ý tưởng của
stage: [README](README.md) · [concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **mới thiết kế, chưa chạy**: chưa có drill nào. Các
con số như 1.43 lần là *tính toán*, không phải số đo — câu trả lời tốt nói rõ điều đó.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage Delivery trong một tới hai phút.

**A1.2** Sau stage CI/CD, một bản lỗi sẽ đi tới người dùng thế nào nếu không có stage này?

**A1.3** Stage này nhận hai tiêu chí nào, và mỗi tiêu chí đòi bằng chứng gì?

### A2. Release theo từng lát

**A2.1** Rollout khác Deployment ở đâu?

**A2.2** Các bước của canary là gì? Vì sao phải chờ trước khi đo?

**A2.3** Vì sao chia traffic ở load balancer chứ không theo số pod?

**A2.4** Canary thêm pod hay chia pod? Điều đó kéo theo gì?

### A3. So với bản cũ, không so với mục tiêu

**A3.1** Gate kiểm hai thứ gì?

**A3.2** Vì sao gate latency so với bản stable chứ không so với T?

**A3.3** Gate tương đối loại bỏ được gì, và không loại bỏ được gì?

### A4. Con số phải là của canary

**A4.1** Hai bản xuất cùng tên metric. Vậy làm sao query biết series nào là của canary?

**A4.2** Nếu chuỗi đó đứt — series của canary không có — thì chuyện gì xảy ra?

**A4.3** "Phiên bản nguy hiểm của lỗi này là phiên bản do người tạo ra." Nghĩa là gì?

**A4.4** Có cách nào để query trả về một con số khoẻ mạnh mà vẫn sai không?

**A4.5** Vì sao cửa sổ query là hai phút?

### A5. Ngưỡng trên giấy và ngưỡng thật

**A5.1** Gate latency viết là 1.2 lần. Vì sao nó thực tế có thể là khoảng 1.43 lần?

**A5.2** Sàn 99% cho tỉ lệ thành công có vấn đề gì trên một cửa sổ nhỏ?

**A5.3** Vì sao drill chạy ở 20 request mỗi giây? Có phải để vượt ngưỡng tối thiểu 20 request không?

**A5.4** Bài học chung của hai gate là gì?

### A6. Quá ít bằng chứng thì dừng

**A6.1** Một AnalysisRun có những kết quả nào?

**A6.2** Ít request quá thì sao? Không có request nào thì sao — có khác nhau không?

**A6.3** Spot lấy mất node của canary giữa chừng. Thiết kế xử lý thế nào?

### A7. Sau khi abort

**A7.1** Sau khi abort, Git và cụm nói gì? Argo CD hiện nó thế nào?

**A7.2** Kết thúc trạng thái đó bằng cách nào? Có cách nào sai không?

### A8. Drill

**A8.1** Mô tả hai drill.

**A8.2** Vì sao drill rollback phải kiểm tỉ lệ lỗi của canary trước khi tin vào việc abort?

**A8.3** Một rollout thất bại vì image không pull được có được tính là drill rollback thành công không?

### A9. Pass mà vẫn hỏng, và giới hạn

**A9.1** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

**A9.2** Stage này chứng minh gì, tính ra gì, và không đo gì?

**A9.3** Stage này có những giới hạn nào đã biết?

**A9.4** Với một đội thật, bạn đổi gì trước tiên?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.4](../eks-sre-llmops-design.md#44-progressive-delivery-argo-rollouts)
