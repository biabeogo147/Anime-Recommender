# Câu hỏi về Scaling

Stage này cho KEDA thêm pod api khi request bắt đầu xếp hàng, và cho Cluster Autoscaler thêm node khi pod không còn
chỗ chạy. Bộ câu hỏi kiểm xem bạn giải thích được vì sao scale theo request đang xử lý chứ không theo CPU, ngưỡng lấy
từ đâu, vì sao khi tín hiệu biến mất thì phải giữ nguyên chứ không scale xuống, và vì sao một nửa hệ thống chạy đúng có
thể trông như cả hệ thống chạy đúng.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về ScaledObject, cấu hình Cluster Autoscaler và resource request, khi code đã có |

Bộ liên quan: [tổng quan project](../common/questions.md), [Load](../4-load/questions.md),
[progressive delivery](../5-delivery/questions.md), [managed so với self-managed](../aws/questions.md). Ý tưởng của
stage: [README](README.md) · [concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **đã chạy**, #14 pass (2026-09-23). Ngưỡng
trigger là **30** in-flight mỗi pod — và câu trả lời tốt nói rõ nó *không* lấy từ in-flight tại điểm gãy, con số đã
trượt phép tái lập, mà lấy từ giới hạn 40 luồng của pod. Câu đáng nhớ nhất của stage: tải gấp ba mà p95 không nhúc
nhích.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage Scaling trong một tới hai phút.

**A1.2** Trước stage này, khi traffic vượt quá điểm gãy thì chuyện gì xảy ra?

**A1.3** Tiêu chí #14 đòi bằng chứng gì?

### A2. Tín hiệu và ngưỡng

**A2.1** Vì sao scale theo số request đang xử lý mà không theo CPU?

**A2.2** Ngưỡng của trigger lấy từ đâu? Định luật Little đóng vai trò gì?

**A2.3** Ngưỡng đo ở chế độ fake. Vì sao nó vẫn dùng được cho traffic thật?

**A2.4** Vì sao query là `sum` chứ không phải trung bình, khi trigger là giá trị trung bình mỗi pod?

### A3. Một vòng điều khiển có độ trễ

**A3.1** Từ lúc tải tăng tới lúc có pod mới nhận traffic, mất những bước nào?

**A3.2** Vì sao ngưỡng phải thấp hơn điểm gãy chứ không đặt đúng ở đó?

**A3.3** Có điều gì làm vòng này mong manh đúng vào lúc nó cần nhất?

### A4. Pod và node

**A4.1** KEDA và Cluster Autoscaler khác nhau thế nào? Vì sao cần cả hai?

**A4.2** Cái gì quyết định Cluster Autoscaler có bao giờ hành động không?

**A4.3** Nếu tám pod vẫn vừa trên hai node thì sao? Có nên tăng request để thấy node scale không?

**A4.4** Trần bốn node có ý nghĩa gì với bài test scaling?

### A5. Đi xuống

**A5.1** Pod được bớt đi theo lịch nào? `cooldownPeriod` của KEDA có liên quan không?

**A5.2** Node được bớt đi theo lịch nào? Có gì chặn việc bớt node không?

**A5.3** Khi một pod bị bớt đi, những request đang trên đường tới nó thì sao?

### A6. Khi tín hiệu biến mất

**A6.1** Nếu series của api biến mất thì KEDA mặc định làm gì?

**A6.2** Bạn sửa thế nào? Vì sao chỉ biến kết quả rỗng thành lỗi thôi là chưa đủ?

### A7. Scale cùng những thứ khác

**A7.1** Nếu scale out xảy ra giữa lúc một canary đang chạy thì sao?

**A7.2** Argo CD và HPA cùng muốn quản số replica của Rollout. Chuyện gì xảy ra, và bạn xử lý thế nào?

### A8. Pass mà vẫn hỏng

**A8.1** Tiêu chí #14 có thể pass sai theo những cách nào?

**A8.2** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

**A8.3** Stage này chứng minh gì, và chỉ giả định gì?

### A9. Giới hạn và nhìn lại

**A9.1** Stage này có những giới hạn nào đã biết?

**A9.2** Nếu có thêm thời gian, bạn đổi gì trước tiên?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing)

---

### A10. Câu đào sâu — Spot bị thu hồi

**A10.1** Node của bạn là Spot. Một lần thu hồi thì xảy ra gì?
