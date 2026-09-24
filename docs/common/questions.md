# Câu hỏi tổng quan về project

Bộ này hỏi về Anime Recommender như một toàn thể: nó là gì, vì sao nó tồn tại cạnh Medical, phần nào đã làm và đo,
phần nào còn trống, và những ý xuyên suốt cả tám stage. Đây thường là mười phút đầu của một buổi phỏng vấn —
người nghe chọn chỗ đào sâu dựa vào những gì bạn nói ở đây.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn kể được cả project một cách mạch lạc, trung thực về trạng thái của nó, và dẫn người nghe tới đúng stage |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về code của app và cấu trúc repo, khi phần hạ tầng đã có |

Bộ theo stage: [Terraform](../1-terraform/questions.md) · [GitOps](../2-gitops/questions.md) · [CI/CD](../3-cicd/questions.md)
· [Load](../4-load/questions.md) · [Delivery](../5-delivery/questions.md) · [SLO](../6-slo/questions.md) ·
[Scaling](../7-scaling/questions.md) · [Tracing](../8-tracing/questions.md). So sánh với Medical:
[managed so với self-managed](../aws/questions.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Phần app **đã làm và đã đo, chạy local**. Bên dưới nó,
tính tới **2026-09-23**: **cả tám stage đã dựng và đã đo trên AWS** — **mười một** tiêu chí đóng bằng số đo trích dẫn được, ba tiêu chí nữa (#2, #15, #16) pass nhưng không giữ output, #7 đo được
một nửa, #13 chưa làm. Câu trả lời tốt nói được con số thật, và nói ba chỗ chưa trọn trước khi bị hỏi — trạng thái
từng criterion đọc ở [`docs/evidence/`](../evidence/).

---

## Phần A — Phỏng vấn

### A0. Mở đầu và định hướng

**A0.1** Kể về bản thân bạn trong hai phút.

**A0.2** Vì sao chuyển từ backend và AI sang DevOps/SRE?

**A0.3** Bạn chưa từng đi trực thật. Sao tôi tin bạn xử lý được sự cố lúc ba giờ sáng?

**A0.4** Bạn có câu nào muốn hỏi lại chúng tôi không?

---

### A1. Giới thiệu

**A1.1** Giới thiệu project trong một phút.

**A1.2** Giới thiệu project trong năm phút.

**A1.3** App là gì, và vì sao một app RAG lại là workload phù hợp cho bài tập SRE?

**A1.4** Vì sao project này tồn tại cạnh Medical?

### A2. Trạng thái thật

**A2.1** Phần nào đã đo, phần nào còn trống? Bạn đã đo được gì?

**A2.2** Kể về những lỗi mà phase app đã sửa.

**A2.3** Kể về một lỗi bạn gặp tình cờ trong lúc làm, và cách bạn xử lý nó.

**A2.4** Vì sao viết thiết kế trọn vẹn trước khi dựng, thay vì dựng tới đâu viết tới đó?

### A3. Kiến trúc

**A3.1** Mô tả kiến trúc từ ngoài vào trong.

**A3.2** Một request từ người dùng đi qua những gì?

**A3.3** Một commit đi tới production qua những gì?

**A3.4** Tám stage là gì, và vì sao theo thứ tự đó?

### A4. Những ý xuyên suốt

**A4.1** "Không khẳng định gì chưa đo" — trong thực tế nó nghĩa là gì?

**A4.2** "Pass mà vẫn hỏng" là gì, và vì sao mỗi stage có một mục riêng cho nó?

**A4.3** "Rỗng không phải là không" — ý này xuất hiện ở đâu?

**A4.4** Fake provider để làm gì, và nó nguy hiểm ở đâu?

**A4.5** Vì sao cụm bị huỷ mỗi tối, và điều đó ép gì lên thiết kế?

### A5. Rủi ro và đánh đổi

**A5.1** Những rủi ro lớn nhất của thiết kế là gì?

**A5.2** Nếu hết thời gian, bạn cắt gì trước, và không bao giờ cắt gì?

**A5.3** Những single point of failure nào bạn đã chấp nhận, và vì sao?

### A6. Câu hỏi hay gặp khác

**A6.1** Khi bắt đầu dựng, bạn đo gì đầu tiên?

**A6.2** Phần khó nhất của thiết kế này là gì?

**A6.3** Project này tốn bao nhiêu tiền, và bạn giữ chi phí thế nào?

**A6.4** Tóm tắt tư thế bảo mật: đã có gì, còn thiếu gì?

**A6.5** Người dùng app thấy gì?

**A6.6** Làm sao biết câu trả lời của LLM có tốt không?

### A7. Nhìn lại

**A7.1** Trong quá trình rà thiết kế, những lỗi nào đáng kể nhất đã được tìm ra?

**A7.2** Nếu làm lại từ đầu, bạn làm khác gì?

**A7.3** Project này nói gì về cách bạn làm việc?

---

[Đáp án](answers.md) · [README gốc](../../README.md) · [Design](../eks-sre-llmops-design.md)

---

### A10. Câu đào sâu — điểm yếu, thứ tự cắt, và phụ thuộc

**A10.1** Điểm yếu lớn nhất của project này là gì?

**A10.2** Nếu phải cắt, bạn cắt gì trước? Và tất cả những thứ này có over-engineer cho một app gợi ý 269 bộ anime không?

**A10.3** SLI của bạn tính một 429 của provider là lỗi của service bạn. Thế đúng không?
