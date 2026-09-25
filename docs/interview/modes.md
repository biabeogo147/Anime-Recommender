# Chế độ đo

Trang tra cứu, đọc **trước** khi nói bất kỳ con số nào. Mở nó để **kiểm điều kiện**, không phải để mất tự tin.

---

## 0. Sáu con số nói được ngay

| Đo được | Giá trị | Chế độ, một câu |
|---|---|---|
| **T**, ngưỡng latency của SLO | **8 s** | real mode, OpenAI `gpt-4o-mini`, 230 request, 0 lỗi |
| **Trần** của hai pod | **93.9 req/s** | fake mode, hai lần chạy khớp nhau, và khớp giới hạn thread pool 94.1 tính trước |
| Canary xấu tự abort | **167 s** ở bước 10% | fake mode + tiêm lỗi 20%; 1.36% *toàn bộ* request lỗi |
| Page tới Discord | **9 m 30 s** | fake mode + tiêm lỗi 50%; tám phút trong đó là số học cửa sổ |
| Scale 2 → 8 pod trên 3 node | **224396** request, **0** lỗi, p95 **1.44–1.47 s** | fake mode, ramp tới 267 req/s |
| Chi phí model | **$0.4186** mỗi nghìn request | real mode `gpt-4o-mini`, giá đọc 22/09/2026 |

Ba phần còn lại của trang là **điều kiện** của những con số này — không phải một danh sách lỗi.

---

## 1. Ba chế độ, và câu luật

Khác project Medical, ở đây **có** một bộ nhãn cố định, định nghĩa một chỗ trong thiết kế §4.1.

| Chế độ | Là gì | Những số ra từ đây |
|---|---|---|
| **real** | Provider thật. `openai` `gpt-4o-mini` là cái đã đo; `gemini` vẫn chọn được | T = 8 s, chi phí $0.4186/1000, trace 957+461 token |
| **fake** | `LLM_PROVIDER=fake`. Tồn tại **chỉ** cho load test và drill, không bao giờ là mặc định | trần 93.9 req/s, canary 167 s, page 9 m 30 s, 8 pod / 3 node |
| **tiêm lỗi** | Vẫn fake, thêm `api_fault_rate`: `0.2` cho drill rollback, `0.5` cho drill alert, về `0` sau đó | 45 request lỗi của canary, 1.36% toàn bộ, error ratio 0.497 |

**Câu luật, nguyên văn thiết kế §4.1:**

> The rule that keeps this honest: **a number produced in `fake` mode and a number produced in real mode are
> different claims**, and every record states which mode it came from, and in real mode which provider and model.

**Fake provider làm bốn việc** (thiết kế §4.1): embedding thành vector hash 384 chiều tất định; LLM ngủ quanh
`FAKE_LATENCY_MS`; lỗi theo xác suất `FAULT_RATE`; và **token bịa ra**, để đường ống chi phí vẫn chạy được.

---

## 2. Bốn điều về fake mode phải nói cho đúng

**2.1 Fake mode không có cuộc gọi ra ngoài nào.** Không phải "gọi một model rẻ hơn" — `get_embeddings` trả
`HashEmbeddings` và `get_llm` trả `FakeLLM`, **cả hai trong process**. Nên cái nó giữ nguyên là thread pool, hàng
đợi, middleware và histogram; cái nó bỏ đi là mạng. Đó chính là điều tôi muốn: phần còn lại là cluster.

**2.2 `FAULT_RATE` một mình không làm gì.** Nó chỉ được `FakeLLM` đọc, mà `FakeLLM` chỉ được dựng khi
`LLM_PROVIDER == "fake"`. Đặt fault rate lên một rollout real mode thì **tiêm zero lỗi**: canary khoẻ, phân tích
pass, bản release được promote — và drill bị lưu lại như bằng chứng rằng rollback hoạt động. Thiết kế nói chuyện này
ba lần, và nó là false pass của tiêu chí #9.

**2.3 `alert.fault` là một mốc thời gian, không phải một tỉ lệ.** Nó là lúc bản lỗi nhận toàn bộ traffic. Và nó
được ghi **sau** vòng poll Healthy, nên lỗi có thể đã tới traffic sớm hơn vài giây: **`T-PAGE` có thể bị báo thấp
hơn thực tế**, không bao giờ cao hơn.

**2.4 Bẫy chi phí, và nó là chỗ sắc nhất của cả bộ vốn từ này.** `config/pricing.yaml` có một entry `fake:` được
đặt giá **y hệt** `gemini-3.5-flash-lite`, và metric fake mode mang nhãn `model="fake"`. Nên một lần chạy fake mode
sinh ra một con số đô la **trông hoàn toàn thật**, từ token bịa — không phân biệt được bằng mắt với số thật. Nó
phá đúng câu luật ở §1, và phá trong im lặng. **Luôn đọc nhãn `model`.**

---

## 3. Bốn con số, và nghĩa đúng của chúng

Bốn con số này đều có thật. Mỗi cái đo **một thứ hẹp hơn** cái tên nó gợi ra — nói đúng phạm vi thì chúng là bằng
chứng, nói rộng ra một chữ thì chúng thành lỗ.

### 3.1 Capacity 88–89 req/s — điều kiện hợp lệ đã trượt, cả hai lần

Quy tắc điểm gãy được viết và commit **trước** khi chạy, kèm hai điều kiện hợp lệ. Một trong hai là *không có
iteration nào bị bỏ trước điểm capacity* — và nó trượt ở **cả hai** lần ramp: lần 1 sớm 4 phút, lần 2 sớm 5 giây.

Nhưng **trần thì vững**, và vững vì ba nguồn độc lập: hai lần chạy đều dừng ở **93.9 req/s** trong khi tốc độ gửi
vẫn leo tới 120; một phép tính viết trước khi chạy cho **94.1** (40 luồng / 0.85 s × 2 pod); và p95 của phần bằng
phẳng đúng bằng p95 lý thuyết của hàm ngủ, 1.42 s tính được so với 1.43 và 1.45 s đo được.

**Nói:** *"the ceiling was 93.9 requests a second, measured twice"*. **Đừng nói:** *"capacity was 88–89"*.

### 3.2 In-flight tại điểm gãy — không tái lập, nên không bao giờ trích

170.5 rồi 117.5, lệch 45%. Cluster cư xử giống nhau cả hai lần — trần 93.9 chứng minh điều đó — nên chỗ bất định
nằm ở **dụng cụ đo**, hai nguyên nhân: p95 đến từ `rate(...[2m])` tức trung bình hai phút, còn in-flight là gauge
đọc **tức thời**; và lưới mẫu 30 giây trên một đoạn dốc gần thẳng đứng (46 → 117 → 228 → 375 → 500 trong hai phút).
Lần chạy thứ ba sẽ cho một con số thứ ba cũng tuỳ ý như vậy, **nên nó không được chạy**.

Ngưỡng 30 của KEDA vì thế lấy từ **giới hạn kiến trúc**: một pod có 40 luồng, mỗi luồng giữ một request, nên
in-flight trên 40 mỗi pod nghĩa là hàng đợi đang hình thành. Đó là một *định nghĩa*, và các phép đo đồng ý với nó —
ở 83 req/s pod giữ 46.5 in-flight mà p95 vẫn 1.46 s, điểm tiếp theo thì tách hẳn.

### 3.3 `1.36%` — của toàn bộ traffic, không phải của canary

Ba con số dễ bị trộn, và chỉ một cái là 1.36%:

| Con số | Nó là gì |
|---|---|
| **1.36%** | phần trăm của **toàn bộ** request phục vụ trong 167 giây canary còn sống — ≈45 lỗi trên ≈3300 |
| 17.9% | tỉ lệ lỗi **của chính canary** (45.0 trên 250.9), so với 20% đã cấu hình |
| ≈7.6% | phần traffic canary **nhận được** trong cửa sổ đó |

### 3.4 SLO 99.5% — một định nghĩa, chưa bao giờ đạt

*"SLO defined at 99.5% over 28 days"* đúng từ ngày nó được commit. *"Sustained 99.5% over 28 days"* thì không, và
**sẽ không bao giờ** đúng trên một cluster bị huỷ khi không dùng. Cái đo được là **đường dẫn alert hoạt động**:
budget cháy thật, các cặp cửa sổ vượt hệ số thật, và một người thật nhận được tin trong 9 phút rưỡi.

---

## 4. Bảy điều kiện, rồi hai lỗ — hai loại khác nhau

4.1–4.7 là **điều kiện**: con số có thật, và nó chỉ đúng trong một phạm vi. 4.8–4.9 là **lỗ**: không có con số
nào cả. Trộn hai loại này là cách nhanh nhất để tự nói quá — "có caveat" nghe như đã đo, còn "chưa đo" thì
không, và người phỏng vấn phân biệt được. Khi bị hỏi, nói rõ mình đang ở loại nào **trước** khi nói nội dung.

### Bảy điều kiện trên số liệu đã có

**4.1 Real mode đi *hai* cuộc gọi ra ngoài.** Mỗi request thật embed câu hỏi qua Hugging Face rồi chat qua OpenAI,
nên **T = 8 s là độ trễ của cả hai**, không phải của riêng model. Cả hai nhánh đều có phân loại lỗi riêng:
`recommender.py` bắt lỗi retrieval thành `UpstreamError(stage="retrieval")` và trả 503 *"Retrieval unavailable"*.
Thiết kế §5 giữ nguyên câu cũ là 500 chưa phân loại, kèm một ghi chú "Changed before stage 4".

**4.2 `9 m 30 s` là biên dưới, vì hai lý do cùng chiều.** Discord chỉ hiện đến phút, nên tin nằm trong
11:14:00–11:14:59Z; nó không thể đến trước alert lúc 11:14:23Z, và Alertmanager giữ nhóm mới 30 giây — còn lại
11:14:53–11:14:59Z, tức **9 m 30 s đến 9 m 36 s**. Cộng nguồn lệch thứ hai ở §2.3.

**4.3 Trivy gate xanh *không* nghĩa là không có lỗ hổng.** Ở mức CRITICAL — mức gate dùng trên mọi build — không
finding nào có bản vá, nên gate xanh **đúng**. Hạ xuống MEDIUM thì gate **đỏ**: mỗi image có 5 finding có bản vá
trong tổng 169 và 165. Nên gate được **chứng minh là biết đỏ**, chứ không phải chỉ đang xanh.

**4.4 Ba tiêu chí của stage 2 chạy mà không giữ output.** #2, #15, #16 — cây Argo CD, HTTPS hai tên public, bốn UI
chỉ qua VPN — đã chạy và khớp kỳ vọng guide, nhưng terminal output không được lưu. Nói định tính được; con số duy
nhất evidence giữ là **8 trên 8** Application. Và false pass chính của #15 — controller tự tìm ra một chứng chỉ
*khác* bằng host match, trong một zone dùng chung với Medical — **chưa được đóng**, vì phép so serial không có trong
evidence.

**4.5 "92 resource, plan lại không thay đổi" đo trước khi có lock file.** Lần đó resolve provider theo khoảng
`~> 6.0`, `aws` ra 6.66.0. Ba file `.terraform.lock.hcl` commit ngày 23/09, **sau** phép đo. Nên tính tái lập chỉ
đúng từ đó trở đi; phép đo không chạy lại vì chuyện này.

**4.6 Bốn UI quản trị không có xác thực đầy đủ.** Argo CD và Grafana có đăng nhập riêng; **Prometheus và
Alertmanager không có gì cả**, nên mọi peer VPN và mọi pod trong VPC có toàn quyền — kể cả tạo silence. Tiêu chí
#16 chứng minh **khả năng tới được**, nó không chứng minh phân quyền.

**4.7 Hai image 1.18 GB so với một image 6.45 GB.** Đừng so 619 MB của api một mình với 6.45 GB — đó là so một
image với hai. Và số của Docker với store overlay2 là dung lượng chưa nén.

### Hai lỗ — không có phép đo nào

**4.8 Hai phép đo còn thiếu, không chỉ một.** M8 (rebuild có bấm giờ → `[T-REBUILD]`, `[N-APPS]`) **chưa chạy**. Và
thời lượng pipeline của tiêu chí #3 vẫn *pending* trong `cicd.md` — tôi có bằng chứng CI chạy đúng, chưa có con số
nó chạy bao lâu.

**4.9 Tiêu chí #13 chưa làm.** Cổng eval chất lượng retrieval, đo bằng `hit@4` trước và sau một pull request làm
giảm chất lượng. Hạng P1, và tôi chủ động chưa làm. Không có bằng chứng nào cho nó trong repo.

---

## 5. Một rủi ro đã biết, ghi lại chứ không bỏ qua

*(Đây là rủi ro về **vận hành**. Danh sách điểm yếu xếp theo mức nghiêm trọng nằm ở
[Dòng CV](cv-lines.md), câu "Điểm yếu lớn nhất" — KEDA không nằm trong ba cái đầu của danh sách đó.)*

**KEDA 2.20.2 tự ghi log rằng nó chưa được test trên Kubernetes 1.36.** Không có gì hoạt động sai, và HPA nó tạo ra
theo đúng metric suốt lần chạy. Tôi ghi nó là **rủi ro đã biết**, và là nghi phạm đầu tiên nếu HPA hành xử lạ ở lần
chạy sau. Cùng loại: KEDA tự restart một lần lúc cài, do chính nó sinh certificate cho webhook rồi thoát để pod khởi
động lại — trong khoảng đó Application đọc `Degraded`, và đó là hành vi đúng.

---

[Dòng CV](cv-lines.md) · [Kiến trúc](architecture.md) · [Thuật ngữ](glossary.md) ·
[Bộ đề](../common/questions.md) · [Evidence](../evidence/)
