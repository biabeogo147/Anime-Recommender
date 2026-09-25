# Câu hỏi về GitOps

Stage này biến một cụm chưa chạy gì thành một cụm chạy đúng những gì Git nói — và những thứ đầu tiên Git nói là
traffic đi vào bằng cửa nào, secret lấy từ đâu, và các tên trỏ về đâu. Bộ câu hỏi kiểm xem bạn giải thích được vì
sao thứ tự dựng phải nằm trong Git, vì sao một controller dựng được hai cửa từ năm Ingress, và vì sao mỗi phép kiểm
của stage này đều cần một phép kiểm thứ hai đi kèm.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về từng file trong `deploy/argocd/`; code đó đã có, nên phần này giờ viết được |

Bộ liên quan: [tổng quan project](../common/questions.md), [managed so với self-managed](../aws/questions.md),
[Terraform](../1-terraform/questions.md), [CI/CD](../3-cicd/questions.md),
[progressive delivery](../5-delivery/questions.md). Ý tưởng của stage: [README](README.md) ·
[concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **đã chạy, và evidence ghi cả ba criteria #2,
#15, #16 là "pass as run, unquoted"**: phép kiểm đã chạy và khớp guide, nhưng terminal output không được giữ lại. Kể
việc đã làm thì được — kèm câu "tôi không giữ bản ghi" — và chỉ đọc ra con số mà evidence có: 8 trên 8 Application. Câu nào bắt bạn phải mở
design mới trả lời được thì đó là câu cần đọc lại.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage GitOps trong một tới hai phút.

**A1.2** Cuối stage Terraform đã có cụm và Argo CD. Vậy còn thiếu gì?

**A1.3** Stage này nhận ba tiêu chí nào, và mỗi tiêu chí kiểm điều gì?

### A2. Git là lối vào duy nhất

**A2.1** Pull và push khác nhau thế nào? Ở project này vì sao pull gần như là bắt buộc?

**A2.2** App-of-apps là gì, và vì sao dùng nó?

**A2.3** CRD liên quan gì tới thứ tự dựng? Lỗi "no matches for kind" nói lên điều gì?

**A2.4** Sync wave hoạt động thế nào, và vì sao chỉ đánh số wave thôi thì chưa đủ?

**A2.5** Wave cuối chứa PrometheusRule của SLO. Nó thực sự cần wave trước không?

**A2.6** Sơ đồ wave là hệ thống hoàn chỉnh. Vậy ở stage 2 thì nó trông thế nào?

### A3. Một controller, hai cửa

**A3.1** AWS Load Balancer Controller biến Ingress thành load balancer thế nào? Vì sao có năm Ingress mà chỉ hai
load balancer?

**A3.2** Việc có năm Ingress ảnh hưởng gì tới teardown?

**A3.3** Vì sao nói controller này quan trọng hơn vẻ ngoài của nó?

**A3.4** Vì sao đăng ký pod bằng IP thay vì bằng node?

**A3.5** ALB "fail open" nghĩa là gì, và readiness gate giúp gì ở đây?

**A3.6** TLS kết thúc ở đâu, và vì sao không có ingress controller nào trong cụm?

**A3.7** Vì sao mọi Ingress phải ghi rõ ARN của chứng chỉ?

**A3.8** Vì sao API có tên riêng `api.anime` thay vì dùng chung với UI?

**A3.9** Ingress nội bộ không bao giờ có load balancer, trong khi cửa public vẫn chạy. Bạn nhìn vào đâu trước?

**A3.10** Ingress trông bình thường, load balancer đã có, nhưng không có listener HTTPS nào. Có thể là gì?

### A4. Secret

**A4.1** External Secrets làm gì, và Git giữ gì về secret?

**A4.2** Thêm một secret mới thì phải làm gì? Nếu quên một bước thì sao?

### A5. Tên miền

**A5.1** Vì sao bản ghi DNS cho load balancer do external-dns viết chứ không phải Terraform?

**A5.2** external-dns làm việc trong zone của Medical. Bạn giữ nó thế nào?

### A6. UI quản trị

**A6.1** Tên public trỏ về địa chỉ private — vì sao thiết kế như vậy, thay vì dùng một private zone?

**A6.2** Có mạng nào mà cách đó không chạy được không?

**A6.3** Laptop bật VPN rồi mà UI vẫn không mở được. Ở phía gateway có thể hỏng những gì?

**A6.4** Vì sao phải "nói cho app biết tên của chính nó"?

**A6.5** Monitoring vốn thuộc về các stage sau. Vì sao nó vào Git ngay ở stage này?

**A6.6** Ingress của Argo CD có đòi Argo CD phải tự quản lý chính nó không?

### A7. Pass mà vẫn hỏng

**A7.1** "Mọi Application đều Synced và Healthy" — câu này có thể đúng trong khi cụm đang hỏng thế nào?

**A7.2** Tiêu chí #15 có thể pass sai theo những cách nào?

**A7.3** "Tắt VPN thì timeout" — vì sao như thế vẫn chưa đủ để chứng minh UI là private?

**A7.4** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

**A7.5** Vì sao nửa âm của #16 phải chạy từ laptop, không phải từ workstation?

### A8. Giới hạn và đánh đổi

**A8.1** Prometheus và Alertmanager không có đăng nhập. Bạn chấp nhận điều đó thế nào?

**A8.2** Stage này chứng minh gì, và chỉ giả định gì?

**A8.3** Security group của mỗi cửa cho phép những gì, và vì sao phép kiểm hành vi không thấy được chúng?

### A9. Nhìn lại

**A9.1** Bài học nào từ Medical đã định hình stage này nhiều nhất?

**A9.2** Nếu đây là cụm cho một đội năm người, bạn đổi gì trước tiên?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.7](../eks-sre-llmops-design.md#47-names-tls-and-the-two-ways-in)

---

### A10. Câu đào sâu — phân quyền, không chỉ khả năng tới được

**A10.1** Ai ở trên VPN cũng mở được cả bốn UI. Cái gì xác thực họ?
