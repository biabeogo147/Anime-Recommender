# Câu hỏi về Load

Stage này đo hai con số mà các stage sau phụ thuộc vào: service nhanh tới đâu khi khoẻ, và bản deploy nhỏ nhất gánh
được bao nhiêu. Bộ câu hỏi kiểm xem bạn giải thích được vì sao T được đọc ở phía server, vì sao phải có đủ mẫu, vì sao
bài test capacity phải là mô hình mở, và làm sao biết một giới hạn đo được là của service chứ không phải của máy chạy
test.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về từng script trong `load/` và từng query, và chỉ viết được khi code đã có |

Bộ liên quan: [tổng quan project](../common/questions.md), [SLO](../6-slo/questions.md),
[scaling](../7-scaling/questions.md), [progressive delivery](../5-delivery/questions.md). Ý tưởng của stage:
[README](README.md) · [concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **đã chạy xong**: #6 (T) pass, #7 (capacity)
**đo được một nửa** — trần 93.9 req/s thì vững, còn capacity 88–89 req/s có điều kiện hợp lệ trượt ở cả hai lần ramp,
nên **chỉ quote trần**; và in-flight tại điểm gãy (170.5 so với 117.5) thì không bao giờ quote. Câu trả lời tốt nói rõ
phương pháp, nói T bằng số, và nói rõ nửa nào của capacity trượt.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage Load trong một tới hai phút.

**A1.2** Vì sao phải đo trước khi viết SLO hay chỉnh autoscaler? Chọn theo cảm giác thì sai ở đâu?

**A1.3** Stage này nhận hai tiêu chí nào, và mỗi tiêu chí đo gì?

### A2. Dữ liệu có tồn tại không

**A2.1** Vì sao phép kiểm đầu tiên của stage này không phải là một bài load test?

**A2.2** Vì sao một kết quả rỗng lại nguy hiểm hơn một kết quả bằng không?

**A2.3** Kiểm dữ liệu có tồn tại thì kiểm trên metric nào? Vì sao không kiểm trên metric lỗi?

**A2.4** Prometheus tìm ra api bằng cách nào? Vì sao dùng PodMonitor chứ không phải ServiceMonitor?

### A3. T

**A3.1** T là gì, và nó được đọc từ đâu?

**A3.2** k6 cũng đo p95. Vì sao không lấy T từ k6?

**A3.3** Chênh lệch dự kiến giữa hai con số đó lớn tới đâu? Nếu nhỏ thì sao phải giữ quy tắc?

**A3.4** Vì sao T phải là một ranh giới bucket? Chọn một giá trị nằm giữa hai bucket thì sao?

**A3.5** Bucket hiện tại có vấn đề gì, và bạn thay đổi chúng thế nào?

**A3.6** Vì sao baseline dừng theo số request hoàn thành chứ không theo thời gian? Vì sao là 200?

**A3.7** Nếu provider bắt đầu từ chối request giữa chừng baseline thì T bị ảnh hưởng thế nào?

**A3.8** Bạn có dự đoán T sẽ rơi vào đâu không?

### A4. Capacity

**A4.1** Bài test capacity đo cái gì, trên cấu hình nào?

**A4.2** Mô hình đóng và mô hình mở khác nhau thế nào? Coordinated omission là gì?

**A4.3** Khi đồ thị đi ngang, làm sao biết đó là giới hạn của service hay của máy chạy k6?

**A4.4** Giới hạn của node group có phải là nghi phạm trong bài test này không?

**A4.5** Con số capacity được dùng vào việc gì?

**A4.6** Endpoint health và metrics dính gì tới capacity? Bạn đổi gì trước khi chạy?

### A5. Hai chế độ

**A5.1** Vì sao baseline dùng model thật (OpenAI `gpt-4o-mini`) còn bài capacity dùng fake provider?

**A5.2** Vì sao không bao giờ so p95 của chế độ fake với T?

**A5.3** Con số capacity ở chế độ fake nói gì, và không nói gì?

### A6. Pass mà vẫn hỏng

**A6.1** Tiêu chí #6 có thể pass sai theo những cách nào?

**A6.2** Tiêu chí #7 có thể pass sai theo những cách nào?

**A6.3** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

### A7. Giới hạn

**A7.1** Stage này chứng minh gì, và chỉ giả định gì?

**A7.2** Metric không sống qua teardown. Điều đó đòi hỏi gì về cách giữ bằng chứng?

**A7.3** Nếu đổi model hay đổi tier của provider thì sao?

### A8. Nhìn lại

**A8.1** Bài học nào từ Medical định hình cách stage này đo?

**A8.2** Với một hệ thống có traffic thật, bạn sẽ đo khác đi thế nào?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing)

---

### A10. Câu đào sâu — vì sao trần là 40 luồng

**A10.1** Một service chỉ chờ I/O mạng thì vì sao lại bị chặn ở một thread pool 40 luồng? Sao không viết async?
