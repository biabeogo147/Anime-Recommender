# Câu hỏi về Tracing

Stage này dùng OpenTelemetry để theo mỗi request qua phần retrieval và phần generation, giữ mọi trace để debug và chỉ
trace của model thật để đọc, rồi biến số token thành một giá ước tính. Bộ câu hỏi kiểm xem bạn giải thích được vì sao
có hai nơi nhận trace, collector tách chúng bằng cách nào, vì sao span metrics không dùng để đo, và vì sao một con số
có mặt chưa chắc là một con số có nghĩa.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về cấu hình collector, span trong code và query chi phí, khi code đã có |

Bộ liên quan: [tổng quan project](../common/questions.md), [Load](../4-load/questions.md), [SLO](../6-slo/questions.md),
[Scaling](../7-scaling/questions.md).
Ý tưởng của stage: [README](README.md) · [concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Stage này **đã dựng và đã đo**, #11 và #12 đều pass
(2026-09-23) trên **OpenAI `gpt-4o-mini`** — không phải Gemini. Việc ghi prompt vẫn chưa được viết. Phép lập luận
đáng nhớ nhất ở đây: **đừng đo sự vắng mặt** — muốn chứng minh trace fake không rò sang Langfuse thì đo một trace
thật *tạo sau nó*.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage Tracing trong một tới hai phút.

**A1.2** Trước stage này, khi latency tăng thì bạn trả lời được những câu hỏi nào, và không trả lời được câu nào?

**A1.3** Stage này nhận hai tiêu chí nào, và mỗi tiêu chí đòi bằng chứng gì?

### A2. Trace và span

**A2.1** Một request `/recommend` sinh ra những span nào? Vì sao chia như vậy?

**A2.2** GenAI semantic conventions là gì, và code hiện tại theo chúng tới đâu?

**A2.3** Vì sao viết span bằng tay thay vì dùng một thư viện instrument LangChain?

### A3. Hai nơi nhận, tách theo pod

**A3.1** Vì sao có cả Tempo lẫn Langfuse?

**A3.2** Collector giữ traffic drill khỏi Langfuse bằng cách nào?

**A3.3** Vì sao không lọc theo tên model?

**A3.4** Hai pipeline có hoàn toàn độc lập khi một bên hỏng không?

**A3.5** Collector sập thì request của người dùng ra sao? Tracing được bật bằng cách nào?

**A3.6** Hiện có sampling không? Nếu thêm thì đặt ở đâu?

### A4. Span metrics

**A4.1** Span metrics dùng để làm gì, và không dùng để làm gì?

**A4.2** Exemplar là gì? Vì sao nói đường link đó mong manh?

### A5. Ghi nội dung

**A5.1** Vì sao Langfuse gần như vô dụng khi chưa ghi prompt?

**A5.2** Ghi prompt và câu trả lời có rủi ro gì? Bạn quyết định thế nào?

### A6. Chi phí

**A6.1** Chi phí mỗi nghìn request được tính thế nào?

**A6.2** Tử số có thể sai thế nào? Mẫu số có thể sai thế nào?

**A6.3** "Span có attribute token" — vì sao câu đó chưa đủ?

**A6.4** Bạn đã có con số chi phí nào chưa?

### A7. Trace sống bao lâu

**A7.1** Trace sống ở đâu và bao lâu? Điều đó đòi hỏi gì về bằng chứng?

### A8. Pass mà vẫn hỏng

**A8.1** Tiêu chí #11 có thể pass sai theo những cách nào?

**A8.2** Tiêu chí #12 có thể pass sai theo những cách nào?

**A8.3** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

**A8.4** Stage này chứng minh gì, và chỉ giả định gì?

### A9. Nhìn lại

**A9.1** Stage này có những giới hạn nào đã biết?

**A9.2** Với một service LLM thật có người dùng, bạn đổi gì?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.2](../eks-sre-llmops-design.md#42-opentelemetry-and-llm-observability)
