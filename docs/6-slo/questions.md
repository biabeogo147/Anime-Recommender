# Câu hỏi về SLO

Stage này biến "service phải đáng tin" thành một ngân sách lỗi được phép, và biến ngân sách đó thành một lần gọi người
chỉ khi nó đang bị tiêu đủ nhanh để đáng quan tâm. Bộ câu hỏi kiểm xem bạn giải thích được burn rate, vì sao mỗi alert
cần hai cửa sổ, vì sao hệ số là cho 28 ngày, và một nền tảng chỉ sống vài giờ mỗi ngày thì chứng minh được gì, không
chứng minh được gì.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về spec Sloth, rule sinh ra và route của Alertmanager; code đó đã có, nên phần này giờ viết được |

Bộ liên quan: [tổng quan project](../common/questions.md), [Load](../4-load/questions.md),
[progressive delivery](../5-delivery/questions.md). Ý tưởng của stage: [README](README.md) · [concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **đã chạy drill**, #10 pass (2026-09-23), và T
đã đo: **8 giây**. Con số cần thuộc: page tới Discord sau **9 phút 30**, trong đó **tám phút là số học cửa sổ**. Câu
trả lời tốt vẫn nói rõ một điều: SLO 99.5% là một *định nghĩa*, chưa bao giờ và sẽ không bao giờ "đạt" trên một cụm bị
huỷ khi không dùng.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage SLO trong một tới hai phút.

**A1.2** Sau stage Delivery, hệ thống vẫn chưa biết những gì?

**A1.3** Vì sao alert kiểu "tỉ lệ lỗi trên X% trong năm phút" không đủ?

### A2. SLO và ngân sách lỗi

**A2.1** SLI, SLO và error budget là gì? Hai SLO của Anime là gì?

**A2.2** Burn rate là gì, và vì sao alert trên burn rate thay vì trên tỉ lệ lỗi?

**A2.3** SLO latency phụ thuộc gì vào stage Load?

**A2.4** Chu kỳ 28 ngày có ý nghĩa gì trên một cụm bị huỷ mỗi tối?

### A3. Hai cửa sổ, hai tốc độ

**A3.1** Vì sao mỗi alert cần hai cửa sổ?

**A3.2** Page và ticket khác nhau thế nào? Cặp nào đi đâu?

**A3.3** Các hệ số 13.44, 5.6, 2.8, 0.93 từ đâu ra? Vì sao không phải 14.4, 6, 3, 1?

### A4. Rule được sinh ra

**A4.1** Vì sao dùng Sloth, và vì sao commit output chứ không chạy Sloth operator?

**A4.2** Rule đã commit rồi thì còn có thể hỏng thế nào?

### A5. Cửa sổ dài hơn dữ liệu

**A5.1** Khi Prometheus mới chạy được vài giờ, một rule có cửa sổ ba ngày hoạt động thế nào?

**A5.2** Vậy cặp nào đáng tin trong một phiên làm việc, và điều đó ảnh hưởng gì tới drill?

### A6. Drill

**A6.1** Mô tả drill alert.

**A6.2** Vì sao drill phải promote thẳng lên toàn bộ traffic, thay vì để ở mức canary?

**A6.3** Vì sao tỉ lệ lỗi của drill là 50% chứ không phải 10%?

**A6.4** Vì sao phải chạy một giờ traffic sạch trước khi tiêm lỗi?

**A6.5** Time-to-alert gồm những phần nào? Vì sao phải ghi từng phần?

### A7. Gửi tới người

**A7.1** Vì sao chỉ alert của SLO được gửi tới Discord? Pod crash-loop thì sao?

**A7.2** Runbook liên quan gì tới alert?

**A7.3** Dead-man's switch là gì, và vì sao ở đây không có?

### A8. Pass mà vẫn hỏng

**A8.1** Tiêu chí #10 có thể pass sai theo những cách nào?

**A8.2** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

**A8.3** Stage này chứng minh gì, và nói rõ là không chứng minh gì?

### A9. Giới hạn và nhìn lại

**A9.1** Stage này có những giới hạn nào đã biết?

**A9.2** Với một hệ thống production thật, bạn đổi gì?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.3](../eks-sre-llmops-design.md#43-slos-and-alerting-deployslo)

---

### A10. Câu đào sâu — runbook, và ai canh người canh

**A10.1** Dẫn tôi qua runbook của page availability. Bạn làm gì, theo thứ tự nào?

**A10.2** Làm sao bạn biết Prometheus đã chết sáu tiếng?
