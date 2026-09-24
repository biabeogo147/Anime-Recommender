# Đáp án Tracing

Đáp án cho [`questions.md`](questions.md), cùng số thứ tự. Mỗi câu mở đầu bằng **Ý chính**: câu nói thành tiếng,
ngôi thứ nhất, thường là đủ. *Nếu được hỏi thêm* dùng khi người phỏng vấn đào sâu. Dòng **Mẹo** là lời nhắc cho
bạn, không nói ra. Tham chiếu dạng `Load A5.2` trỏ tới bộ tương ứng.

Stage này **đã chạy**: criteria #11 (một trace thật ở cả hai nơi nhận, token khác không) và #12 (chi phí mỗi nghìn
request ở real mode) đều **pass**, 2026-09-23 ([evidence](../evidence/tracing.md)). Ghi prompt vẫn **chưa viết**. Chỗ `[điền: …]` là số liệu phải lấy từ lần chạy thật trước khi
dùng — đừng nói con số bạn chưa đo. Ghi chú **[kiểm chứng]** là hành vi của công cụ cần xác nhận trước khi nói chắc. Số
thập phân viết bằng dấu chấm.

Thuật ngữ dùng thống nhất trong bộ này: **span retrieval** và **span generation** cho hai span viết tay; **nơi nhận**
cho Tempo hoặc Langfuse; **dấu** cho resource attribute đánh chế độ của pod; **drill** cho traffic ở chế độ fake.

**Số liệu đã có** — đo local ở phase app ([`../evidence/local.md`](../evidence/local.md)), đọc từ counter trên
`/metrics`, chưa qua trace hay collector nào, được phép nói:

| Số | Giá trị | Dùng ở |
|---|---|---|
| Token sau hai request, `gemini-3.5-flash-lite`, local | 1829 input, 790 output | A6.4 |
| Chi phí ước tính theo giá niêm yết của tier trả phí, local | 0.0025 USD cho hai request, khoảng 0.0013 USD mỗi request | A6.4 |

**Số liệu đã đo trên AWS** ([`../evidence/tracing.md`](../evidence/tracing.md), 2026-09-23, real mode **OpenAI
`gpt-4o-mini`** — không phải Gemini):

| Đọc được | Giá trị | Dùng ở |
|---|---|---|
| Trace thật, trong Tempo | `d19d2834e2fb4216c71cb8fad4bf2f95`: `POST /recommend` (SERVER), `rag.retrieve` (INTERNAL, `rag.top_k=4`, `rag.docs_returned=4`), `chat gpt-4o-mini` (CLIENT) | A1.3, A8.1 |
| Token trên span generation | `gen_ai.usage.input_tokens=957`, `gen_ai.usage.output_tokens=461` | A1.3, A8.1 |
| Cùng trace đó trong Langfuse | **7 observation**, `chat gpt-4o-mini` kiểu `GENERATION`, **1418 token** (= 957 + 461) và **$0.00042** | A1.3, A8.1 |
| Request fake cùng phiên, trong Tempo | có, với `anime.llm.provider = fake` | A8.1 |
| Cùng trace fake đó trong Langfuse | `http 200`, **observation: 0** | A8.1 |
| Một trace thật tạo **sau** trace fake | `http 200`, **7 observation** — chứng minh ingestion đã vượt mốc thời gian đó | A8.1 |
| Drill 5 phút: request / span qua collector / trace riêng biệt trong Langfuse | **6343 / 6076 / 0** | A1.3 |
| **Chi phí mỗi 1000 request** | **$0.4186**, nhãn `model="gpt-4o-mini"` | A1.3, A6.4 |
| Tổng chi phí lần đo | $0.01739 cho 40 request → $0.435 mỗi nghìn — khớp tới hai chữ số | A6.4 |
| `model="fake"` trong cùng cửa sổ | **$0** | A6.4 |
| Giá dùng, và **ngày đọc** | `gpt-4o-mini` $0.15 / 1M input, $0.60 / 1M output, đọc **2026-09-22** | A6.4 |
| Dashboard | 4 panel; hai panel cạnh nhau trên cùng dữ liệu, panel chi phí lọc `fake` ra, panel p95 giữ nó lại | A1.3 |

**Ba đường tính độc lập khớp nhau:** $0.01739 / 40 request = $0.435 mỗi nghìn; tỉ số trên cửa sổ `increase()` mười
phút ra $0.4186; và Langfuse tự tính $0.00042 cho một request bằng bảng giá riêng của nó.

---

## Phần A — Phỏng vấn

### A1. Tổng quan

**A1.1** **Ý chính:** "Stage này tôi đã dựng và chạy, hai tiêu chí #11 và #12 đều pass. Mỗi request `/recommend` có
một span retrieval và một span generation. Collector gửi mọi trace tới Tempo trong cụm để
debug, và chỉ trace của model thật tới Langfuse để đọc; nó tách hai loại bằng một dấu đặt trên từng pod. Số token nhân giá
niêm yết thành chi phí ước tính mỗi nghìn request. Phần khó không phải là thu dữ liệu, mà là quyết định cái gì đi đâu. Và
không bao giờ nhầm một con số có mặt với một con số có nghĩa."

*Nếu được hỏi thêm:* tách theo pod ở A3.2, chi phí ở A6.1, con số có mặt mà vô nghĩa ở A6.3.

**Mẹo:** câu đầu tiên đặt khung cho cả buổi. Ở stage này giờ chỉ còn hai trạng thái — **đã dựng và đã đo**, và
**ghi prompt thì chưa viết**. Nói rõ cả hai.

**A1.2** **Ý chính:** "Metrics đã tách được thời gian retrieval với thời gian model ở mức tổng, vì mỗi phần có histogram
riêng. Nhưng chúng không nói được *một request cụ thể* chậm ở đâu, và không có cách nào đi từ một điểm chậm trên đồ thị tới
đúng request đó. Chi phí có counter trong Prometheus nhưng chưa nằm trên dashboard nào. Và nội dung của một câu trả lời tệ —
thứ đáng đọc nhất khi một service LLM chạy sai — hoàn toàn không được ghi."

**A1.3** **Ý chính:** "#11: một trace `/recommend` ở **real mode, OpenAI `gpt-4o-mini`**, có span retrieval và
span generation với số token *khác không* — 957 vào, 461 ra — kiểm ở cả Tempo lẫn Langfuse. #12: dashboard hiện chi
phí mỗi nghìn request ở **real mode**, kèm nhãn `model` và ngày của file giá.

*Nếu được hỏi thêm:* span generation mang `gen_ai.provider.name=openai`, `gen_ai.request.model=gpt-4o-mini`,
**957** token vào và **461** token ra trong Tempo; cùng trace id đó trong Langfuse có **7 observation** với
**1418** token — đúng bằng 957 + 461 — và $0.00042. Request fake cùng phiên có trong Tempo với
`anime.llm.provider = fake` và **0 observation** trong Langfuse. Chi phí: **$0.4186** mỗi nghìn request, real mode
`gpt-4o-mini`, giá đọc ngày **2026-09-22**.

### A2. Trace và span

**A2.1** **Ý chính:** "Một span request, bên trong có span retrieval — số tài liệu yêu cầu và trả về — và span generation —
model, token vào, token ra. Cộng vài span nhỏ do framework web tự thêm. Giá trị nằm ở việc chia: retrieval và generation hỏng
khác nhau và tốn khác nhau, nên câu hỏi 'nửa nào chậm đi?' có câu trả lời cho từng request, không chỉ ở mức trung bình."

*Nếu được hỏi thêm:* span retrieval bọc cả lời gọi embedding lẫn tìm kiếm vector, nên nó chưa tách hai phần đó.
UI chưa được instrument, nên trace bắt đầu ở api; trace id được trả về trong response và hiện ngay dưới câu trả
lời, nên một request mà ai đó phàn nàn có thể được tìm ra. Probe health, readiness và metrics được loại khỏi
instrument, vì chúng chạy liên tục và sẽ lấn át trace thật.

**A2.2** **Ý chính:** "Là bộ tên attribute mà OpenTelemetry thống nhất cho AI tạo sinh: tên thao tác, model, provider, số
token, và quy tắc đặt tên span. Span generation theo quy tắc tên và mang thao tác, model và token. Còn hai chỗ chưa theo: nó
chưa có `gen_ai.provider.name` — bản cũ của quy ước gọi là `gen_ai.system` — và dùng loại span `INTERNAL` mặc định thay vì
`CLIENT`. Bản thân bộ quy ước vẫn đang ở trạng thái phát triển, nên tôi kiểm theo phiên bản được ghim lúc dựng."

**A2.3** **Ý chính:** "Những con số project này dựa vào không nên phụ thuộc vào việc một thư viện có theo kịp LangChain hay
không. Thư viện đó sẽ thêm chi tiết, và nó vẫn là một lựa chọn để đánh giá, nhưng không phải một phụ thuộc. Hai span viết tay
đã mang đủ thứ tôi cần."

### A3. Hai nơi nhận, tách theo pod

**A3.1** **Ý chính:** "Hai việc khác nhau. Tempo trong cụm để debug, kể cả mọi drill. Langfuse bên ngoài để đọc
prompt và câu trả lời thật. Drill làm việc tách này thành bắt buộc: chúng dồn tải bằng fake provider, hàng chục
request mỗi giây, có khi kéo dài tới một giờ, mỗi request lại là vài span. Tier miễn phí của Langfuse giới hạn số
observation mỗi tháng **[kiểm chứng: hạn mức hiện tại]**, nên chỉ vài buổi drill là có thể tiêu hết — cho một
model không tồn tại."

**A3.2** **Ý chính:** "Chế độ là thuộc tính của *pod*, không phải của một span nào. Nên chart đặt một resource attribute ghi
provider của pod, lấy từ cùng giá trị chọn provider, và attribute đó nằm trên mọi span pod đó phát ra. Collector có hai
pipeline trace đọc cùng một receiver: một gửi mọi thứ tới Tempo, một chỉ giữ những gì mang dấu model thật rồi mới gửi tới
Langfuse."

*Nếu được hỏi thêm:* tôi lọc theo danh sách cho phép chứ không theo danh sách chặn: pod nào thiếu dấu — ví dụ
chart quên đặt — thì bị giữ lại, không bị gửi ra ngoài **[kiểm chứng: cách so sánh giá trị rỗng trong ngôn ngữ
lọc của collector]**. Pipeline đi ra ngoài cũng là pipeline bỏ header.

**A3.3** **Ý chính:** "Vì tên model chỉ nằm trên span generation. Lọc theo nó thì bỏ đúng span đó và chuyển tiếp
phần còn lại của mỗi trace drill — span request, span retrieval, span của framework. Langfuse vẫn đầy, với những
trace không có generation. Bộ lọc trông như đang chạy, vì span generation đã biến mất. Một bộ lọc phải dựa vào
thứ có mặt ở mọi chỗ nó cần tác động."

**Mẹo:** đây là câu hay nhất của stage — một bộ lọc chạy đúng trên đúng một span và sai trên phần còn lại.

**A3.4** **Ý chính:** "Không hoàn toàn. Mỗi exporter có hàng đợi riêng, và khi hàng đợi Langfuse đầy thì exporter
đó bỏ dữ liệu chứ không chặn pipeline Tempo. Chỗ hai bên dính nhau là bộ nhớ chung của collector: hàng đợi phình
ra thì bộ giới hạn bộ nhớ, vốn tính trên cả process, từ chối dữ liệu cho cả hai pipeline. Lúc đó api gửi lại, và
Tempo có thể mất span hoặc có span trùng. Request của người dùng không bị ảnh hưởng, vì export chạy nền **[kiểm
chứng: hành vi khi hàng đợi đầy ở phiên bản collector được ghim]**."

**A3.5** **Ý chính:** "Request không bị gì. Tracing chỉ bật khi biến môi trường chỉ endpoint của collector được đặt. SDK gửi
span theo lô, chạy nền, với hàng đợi có giới hạn: collector sập thì span bị bỏ, request không chậm đi."

*Nếu được hỏi thêm:* api dùng exporter OTLP qua HTTP, nên collector phải mở receiver HTTP, và SDK tự nối đường
dẫn cho traces. Trỏ nhầm sang cổng gRPC thì span mất trong im lặng, chỉ để lại một dòng log **[kiểm chứng]**.

**A3.6** **Ý chính:** "Hiện chưa — mọi trace đều được giữ, vì traffic nhỏ và Tempo chỉ sống trong một phiên. Nếu
thêm, tôi đặt tail sampling ở collector, trong pipeline Tempo, để giữ trọn những trace lỗi hoặc chậm và bỏ bớt
trace bình thường. Pipeline Langfuse thì đã được lọc theo chế độ rồi."

*Nếu được hỏi thêm:* tail sampling đòi mọi span của một trace tới cùng một instance collector, nên khi có hơn một
replica phải thêm một lớp cân bằng tải theo trace id.

### A4. Span metrics

**A4.1** **Ý chính:** "Để tìm trace, không để đo. Collector biến span thành metric, và các series đó trùng với histogram của
api mà không khớp — bucket khác, điểm bắt đầu và kết thúc khác. Thay vì cố làm hai phép đo của cùng một thứ khớp nhau, tôi
giao mỗi thứ một việc: mọi SLI và mọi gate đọc histogram của api; span metrics chỉ để một panel Grafana nhảy được từ một
bucket chậm sang một trace ví dụ."

*Nếu được hỏi thêm:* số series của span metrics được giữ trong tầm kiểm soát vì tên span là template của route và tên model.
Thêm một resource attribute như tên pod vào chiều của nó thì số series nhân lên.

**A4.2** **Ý chính:** "Exemplar là trace id của một request đã góp vào một điểm trên đồ thị. Đường link đó cần ít
nhất bốn thiết lập ở ba thành phần: connector phải bật exemplar, exporter phải xuất theo định dạng OpenMetrics,
Prometheus phải bật lưu exemplar, và datasource Prometheus của Grafana phải trỏ trace id sang Tempo. Cộng với
việc chính panel phải bật exemplar trên query **[kiểm chứng]**. Thiếu một cái thì không có lỗi nào: đồ thị vẫn vẽ
bình thường, chỉ là không có gì để bấm — và không ai để ý cho tới lúc cần."

### A5. Ghi nội dung

**A5.1** **Ý chính:** "Vì không span nào mang prompt hay câu trả lời. Langfuse sẽ nhận thời gian và số token,
không có chữ nào để xem — mà chữ mới là thứ đáng đọc nhất khi một service LLM trả lời sai. Nên stage 8 viết việc ghi
nội dung sau cờ `OTEL_CAPTURE_CONTENT` — tắt trong code, bật bởi chart ở đây."

**A5.2** **Ý chính:** "Ô nhập là văn bản tự do. 'Nội dung là sở thích anime' mô tả ô đó *dùng để làm gì*, không
phải người ta gõ gì vào. Bật ghi thì bất cứ thứ gì người dùng gõ đều được chép sang một dịch vụ bên thứ ba. Tắt
thì một câu trả lời tệ chỉ đo được thời gian, không đọc được. Tôi quyết định công khai: một cờ, bật cho bản demo
một người vận hành, ghi rõ trên trang có ô nhập, và mặc định tắt ở bất kỳ nơi nào có quy định. Quyết định phải
được đưa ra có chủ đích, không thừa hưởng từ một mặc định."

### A6. Chi phí

**A6.1** **Ý chính:** "Token nhân giá niêm yết cho ra chi phí ước tính theo từng model. Chi phí mỗi nghìn request
là một nghìn nhân tốc độ tăng của counter chi phí, chia cho tốc độ của số request thành công *có label model* —
cả hai giới hạn vào cùng các model thật. Giá lấy từ một file được commit và ghi ngày, không lấy tự động."

**A6.2** **Ý chính:** "Tử số: fake provider được định giá y như model thật, nên nếu không lọc thì mỗi drill cộng
thêm những đô-la trông rất thật từ token bịa ra. Mẫu số: counter request quen thuộc không có label model, nên
không lọc được — nó đếm mọi request drill và pha loãng con số. Nên mẫu số là một số đếm request có mang model. Tỉ
số chỉ sạch bằng vế kém sạch hơn của nó."

*Nếu được hỏi thêm:* một model không có trong file giá — hoặc có nhưng giá bằng không — thì dashboard hiện `0.00` đầy tự tin.
Token suy nghĩ của model được tính tiền như output; code có tính chúng vào chi phí hay không thì phải kiểm **[kiểm chứng]**.
Panel hiện luôn label nó đang cộng, để bộ lọc nhìn thấy được chứ không phải giả định. Về fake provider: Load A5.3.

**Mẹo:** "tỉ số chỉ sạch bằng vế kém sạch hơn của nó" là câu đáng nhớ.

**A6.3** **Ý chính:** "Vì khi model không báo usage, code cũ ghi token bằng không — stage 8 đã sửa để chỉ ghi khi
model báo, nhưng counter metrics vẫn cộng số không. Attribute *có mặt* và bằng không
trông y hệt một giá trị thật tình cờ bằng không. Nên 'span có attribute token' đúng cả khi việc thu token hỏng
hoàn toàn. Chi phí tính từ cùng số token đó, nên dashboard báo một ngày rẻ bất thường mà thực ra không có thật.
Phép kiểm đòi số token *khác không*, từ request model thật."

*Nếu được hỏi thêm:* chế độ fake còn tệ hơn — fake provider bịa ra số token trông hợp lý, nên một ảnh chụp màn
hình không chứng minh gì. Cùng họ với "rỗng không phải là không" ở Load A2.2.

**A6.4** **Ý chính:** "Chỉ có số local. Sau hai request Gemini, 1829 token vào và 790 token ra, ước tính 0.0025
USD theo giá niêm yết — khoảng 0.0013 USD mỗi request. Đó là giá của tier trả phí, trong khi project chạy trên
tier miễn phí: nó là số tiền traffic *sẽ* tốn, không phải số đã trả. Số này đọc từ counter khi chạy local, chưa
qua trace nào, và hai request thì quá ít để nhân lên thành chi phí mỗi nghìn request. Con số trên dashboard thì
chưa có."

*Nếu được hỏi thêm:* panel hiện legend `model=gpt-4o-mini` với giá trị 0.42–0.45, khớp con số truy vấn trả về:
**$0.4186** mỗi nghìn request, real mode, giá đọc **2026-09-22**. Và panel p95 ngay cạnh đó *giữ* `model=fake` lại —
nên cái filter nhìn thấy được, không phải một dòng cấu hình ai đó phải tin.

### A7. Trace sống bao lâu

**A7.1** **Ý chính:** "Tempo giữ block trong một `emptyDir`, chết cùng pod — mỗi lần teardown là mất, và cả khi
pod bị dời sang node khác. Langfuse Cloud giữ trace model thật qua các lần teardown, trong thời hạn gói của nó
cho phép. Nên bằng chứng được thu *trong* phiên, từ cả hai nơi, không đọc lại vào hôm sau. Một trace có trong
Langfuse ngày mai mà không có trong Tempo là trạng thái bình thường."

*Nếu được hỏi thêm:* Cluster Autoscaler bớt một node giữa phiên cũng có thể xoá bằng chứng trong Tempo — Scaling A5.2.

### A8. Pass mà vẫn hỏng

**A8.1** **Ý chính:** "Ba cách. Token bằng không nhưng có mặt — 'trace có attribute GenAI' pass trong khi thu
token hỏng hoàn toàn. Chế độ fake, nơi token bị bịa ra. Và việc tách hai nơi nhận: 'Langfuse không có trace
drill' cũng là hình dạng của một export Langfuse bị hỏng. Nên phép kiểm đòi giá trị khác không, ghi rõ chế độ,
kiểm cả Tempo *lẫn* Langfuse, và tra một request fake cùng phiên theo trace id — có trong Tempo, không có trong
Langfuse — cạnh một trace thật đã tới Langfuse."

*Nếu được hỏi thêm:* trace thật có đủ ba span ở Tempo với 957 + 461 token, và 7 observation ở Langfuse với 1418
token. Trace fake cùng phiên: có ở Tempo, **0 observation** ở Langfuse. Và phép kiểm làm nó thành câu trả lời chứ
không phải sự chậm trễ là một trace **thật tạo sau** trace fake — khi trace đó đã hiện, ingestion đã vượt mốc thời
gian ấy.

**A8.2** **Ý chính:** "Hai cách. Một lần chạy ở chế độ fake cho ra con số đô-la thật từ token bịa, không phân
biệt được bằng số với con số thật — luôn đọc label model. Và một model không có giá trong file, cho ra `0.00` đầy
tự tin."

**A8.3** **Ý chính:** "Một giá trị có mặt nhưng không có nghĩa — một số không mặc định, một đô-la làm từ token
giả, một bộ lọc bỏ một span và cho qua phần còn lại, một đồ thị vẫn vẽ nhưng mất đúng đường link mà nó được dựng
ra để có. Cách bắt lần nào cũng như nhau: hỏi giá trị đó nói *về* cái gì, trước khi hỏi nó *là* bao nhiêu."

**Mẹo:** đây là stage cuối của phần P0. Kể được dạng pass sai của cả tám stage theo thứ tự là một kết thúc rất mạnh cho buổi
phỏng vấn.

**A8.4** **Ý chính:** "Stage này đã chứng minh cả ba: một request model thật sinh ra trace có span retrieval và
span generation, span generation mang 957 và 461 token khác không, ở cả Tempo lẫn Langfuse — và hai nơi nhận đồng ý
với nhau, vì 1418 token Langfuse báo đúng bằng 957 + 461, nên chúng đang giữ *cùng một request* chứ không phải chỉ
cùng có dữ liệu. Một request fake cùng phiên có trong Tempo mà không có trong Langfuse, và trên cả cửa sổ drill là
6343 request ra 0 trace. Dashboard hiện $0.4186 mỗi nghìn request cho model thật.

Nó vẫn giả định giá niêm yết còn đúng — giá được đọc tay và ghi ngày 2026-09-22 — và số token provider báo đúng là số
nó sẽ tính tiền. Và ba sự cố trên đường đi đều tạo ra câu trả lời *sai nhưng hợp lý* chứ không tạo ra lỗi: Langfuse ở
sai region nên export bị chặn trong im lặng; endpoint list trả `modelId` null nên đọc ra 'provider không báo usage',
điều không phân biệt được với sự thật; và một lần đổi chế độ chỉ promote được một nửa, nên spec đã là `fake` mà 90%
traffic vẫn về pod real mode. Phép kiểm đúng cho cái cuối là `stable = latest`, không phải `provider=fake`."

### A9. Nhìn lại

**A9.1** **Ý chính:** "Ghi prompt chưa được viết. Tempo không giữ gì qua teardown. Chi phí là ước tính theo giá niêm yết, cho
một project chạy trên tier miễn phí. Và hai pipeline dính nhau qua bộ nhớ của collector khi Langfuse sập lâu."

**A9.2** **Ý chính:** "Tempo với storage bền — object storage — để trace sống qua đêm. Ghi nội dung có che thông
tin cá nhân trước khi gửi ra ngoài, không chỉ một cờ bật tắt. Tail sampling ở collector thay vì giữ mọi trace.
Instrument cả UI để trace bắt đầu từ phía người dùng. Và giá lấy từ billing thật thay vì giá niêm yết đọc tay."

---

[Câu hỏi](questions.md) · [README](README.md) · [Concepts](concepts.md) ·
[Design §4.2](../eks-sre-llmops-design.md#42-opentelemetry-and-llm-observability)
