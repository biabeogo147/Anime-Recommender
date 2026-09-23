# Câu hỏi về CI/CD

Stage này biến một thay đổi đã merge thành một image đã test, đã scan, đã ký, cộng một dòng thay đổi trong Git — rồi
dừng lại. Nó không bao giờ deploy. Bộ câu hỏi kiểm xem bạn giải thích được vì sao CI dừng ở một commit, vì sao mọi
phép kiểm phải từng được thấy thất bại, và một chữ ký phải nói gì thì mới có giá trị.

Đáp án nằm ở [`answers.md`](answers.md), cùng số thứ tự.

| Phần | Kiểm tra điều gì |
|---|---|
| **A. Phỏng vấn** | Bạn trình bày được các quyết định của stage và lý do đằng sau từng quyết định, bằng lời của mình |
| **B. Chi tiết** | *Chưa viết.* Phần này hỏi về từng job trong `.github/workflows/`, và chỉ viết được khi code đã có |

Bộ liên quan: [tổng quan project](../common/questions.md), [managed so với self-managed](../aws/questions.md),
[Terraform](../1-terraform/questions.md), [GitOps](../2-gitops/questions.md). Ý tưởng của stage: [README](README.md) ·
[concepts](concepts.md).

**Cách dùng.** Trả lời thành tiếng trước khi mở đáp án. Pipeline **đã chạy**: #3, #4, #5 đóng
([evidence](../evidence/cicd.md)), riêng thời lượng pipeline chưa đo. Câu trả lời tốt tách rõ cái đã đo với cái
còn *pending*, và không đoán con số chưa có.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** Trình bày stage CI/CD trong một tới hai phút.

**A1.2** Trước stage này, việc đưa một image lên cụm diễn ra thế nào, và sai ở đâu?

**A1.3** Stage này nhận những tiêu chí nào, và mỗi tiêu chí kiểm điều gì?

### A2. CI dừng ở một commit

**A2.1** Vì sao CI không deploy?

**A2.2** Vì sao dùng digest mà không dùng tag?

**A2.3** Rollback trong thiết kế này là gì, và nó có giới hạn nào?

**A2.4** Trong một lần canary, Git và cụm có thể nói khác nhau. Điều đó có phải là lỗi không?

### A3. Mọi phép kiểm phải nói được "không"

**A3.1** "Phép kiểm đã từng được thấy thất bại" nghĩa là gì, và vì sao nó quan trọng?

**A3.2** Phép kiểm index đã được thấy thất bại. Vì sao tiêu chí #5 vẫn đòi làm lại theo cách khác?

**A3.3** Vì sao #5 đòi đúng dòng `IndexValidationError`, chứ không chấp nhận bất kỳ lần build nào thất bại?

**A3.4** Trivy bỏ qua các lỗ hổng chưa có bản vá. Đúng hay sai?

**A3.5** Vậy vì sao bạn gọi gate của Trivy là "chưa chứng minh"?

**A3.6** Ghi lại "số lỗ hổng critical có bản vá" có đủ không?

**A3.7** Token Hugging Face được dùng lúc build. Làm sao bạn biết nó không nằm lại trong image?

### A4. Chữ ký phải nói ai, và từ đâu

**A4.1** Ký keyless hoạt động thế nào?

**A4.2** Khi verify một chữ ký keyless, phải kiểm những gì?

**A4.3** Vì sao verify theo tên repo thôi là chưa đủ?

**A4.4** Ký keyless thì chữ ký được ghi vào một log public. Vì sao Anime chấp nhận mà Medical thì không?

**A4.5** SBOM và attestation dùng để làm gì? Chữ ký trên attestation chặn được gì, và không chặn được gì?

**A4.6** Trong cụm có gì từ chối image chưa ký không?

### A5. Người ghi duy nhất vào `main` không phải là người

**A5.1** `main` được bảo vệ. Vậy commit của bot vào bằng đường nào?

**A5.2** `[skip ci]` có thật sự cần không?

### A6. Pull request từ bên ngoài

**A6.1** Một pull request từ fork chạy tới đâu? Pull request từ chính repo thì sao?

**A6.2** Điều đó kéo theo gì cho người merge?

### A7. Kích thước image và eval gate

**A7.1** Tiêu chí #4 nói về kích thước image. Bạn đã đo gì, và còn phải đo gì?

**A7.2** Eval gate kiểm gì, và vì sao nó là P1?

**A7.3** Baseline của eval gate có thể sai theo cách nào?

### A8. Pass mà vẫn hỏng

**A8.1** Tiêu chí #3 có thể pass sai theo những cách nào?

**A8.2** Các lần pass sai của stage này có chung một hình dạng. Đó là gì?

**A8.3** Stage này chứng minh gì, và chỉ giả định gì?

### A9. Giới hạn và nhìn lại

**A9.1** Pipeline này phụ thuộc vào những dịch vụ bên ngoài nào? Mất một cái thì sao?

**A9.2** Nếu phải đưa pipeline này lên production cho một đội, bạn thêm gì trước tiên?

---

[Đáp án](answers.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.6](../eks-sre-llmops-design.md#46-cicd-github-actions-githubworkflows)
