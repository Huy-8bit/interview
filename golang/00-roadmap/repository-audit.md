# Repository audit

Kiểm tra ngày2026-09-29 trên **Go1.26.4 darwin/arm64**. Phạm vi thay đổi của task: `golang/`. [Structured evidence](../tools/verification.json) và [verification tools](../tools/README.md).

## Delivery inventory

| Hạng mục | Kết quả |
|---|---:|
| Files created (không gồm cache/generated profiles) | 316 |
| Markdown documents | 296 |
| Files expanded có sẵn trước task | 0 — Golang ban đầu trống |
| Required paths | 276/276 |
| Canonical P0 deep dives | 27 |
| Mermaid diagrams added | 90 |
| System designs created | 9 |
| Production scenarios added | 12 |
| Question prompts toàn tài liệu | 1270 |
| Distinct question text theo structural parser | 1151 |

27 P0×30=810 câu hỏi theo đúng10 basic/mid,10 senior,5 production scenarios,5 follow-ups. Hai banks riêng có100 Go và50 Backend với consecutive numbering/expandable answers; một số prompts xuất hiện lại trong mocks để luyện retrieval. “Distinct text” không khẳng định mọi câu hỏi khác nhau về semantic concept.

## Content and structure checks

- Tất cả276 paths yêu cầu tồn tại; thêm module READMEs, references, runnable examples và tools.
- Local Markdown links/anchors không broken; code fences cân bằng; không unresolved task markers.
- P0 đủ concept/mental model/why/how/internals/diagram/code/use case/failures/trade-offs/misconceptions/when-not/debugging/questions/takeaways. Mỗi bài đạt structural depth gate; có review tập trung semantics runtime/concurrency/pools.
-9 designs đều có14 mục yêu cầu, Go implementation và ít nhất5 diagrams. Migration/20k RPS có capacity arithmetic, failure injection và acceptance gates riêng.
-54 bài bổ trợ được bổ sung applied drill sau depth review. Không còn bài bị structural audit gắn cờ quá ngắn.
- Không có full documents trùng nội dung; không paragraph dài trùng nguyên văn Python hiện tại. Standard section labels/rubrics có chủ đích lặp, cross-links nối các chủ đề liên quan.

## Executed validation

| Check | Observed result |
|---|---|
| `go test -race ./...` trong examples | Pass; pool, HTTP reuse/cancel/body bound, algorithms và core examples |
| `go vet ./...` | Pass |
|20 Go Markdown blocks | Compile pass; snippets được cấp imports/argument harness như mô tả |
| FuzzLowerBound,5s | Pass,62611 executions trong run được quan sát |
| FuzzDecimalRoundTrip,5s | Pass,207875 executions trong run được quan sát |
| Negative race demo, build tag racedemo | Expected failure, DATA RACE; default suite không include test này |
| BenchmarkFormat và CPU/heap capture | Commands chạy thành công; profiles đọc được bằng pprof |
| Execution trace capture | Pass |
| HTTP server/SIGTERM smoke |200 health response, process exit0 sau SIGTERM |
| Mermaid12.0.0 |90 diagrams parse pass,0 syntax errors |

HTTP tests và Chromium parser cần quyền chạy loopback/browser process ngoài sandbox mặc định; lượt đầu bị môi trường chặn và lượt chạy với quyền phù hợp đã pass. Không thay đổi tests để bỏ qua hành vi cần kiểm.

## Python boundary

Snapshot ban đầu gồm275 Python files. Trong khi task đang chạy, Python xuất hiện thay đổi/xóa/thêm so với snapshot dù toàn bộ lệnh ghi của task này chỉ nhắm vào Golang. Vì vậy **không tuyên bố toàn thư mục Python bất biến**. Không restore, sửa hoặc di chuyển bất kỳ Python file nào để tránh can thiệp công việc ngoài phạm vi. Audit giữ baseline và báo drift như warning riêng; trạng thái này có thể tiếp tục đổi nếu có tác vụ khác hoạt động.

## Verification limits

SQL helpers compile nhưng chưa chạy với PostgreSQL driver/server thật. Không có live Redis/Kafka/Kubernetes integration,20k RPS benchmark hoặc migration5B records được thực thi. Các design ghi rõ assumptions và cần validation trên hạ tầng/dữ liệu đại diện. Benchmark local chỉ là smoke cho harness/profile workflow, không làm sizing recommendation. Mermaid được kiểm syntax bằng parser; rendering giữa Markdown hosts có thể khác.

## Recommended next study step

[Top20 Go, Top10 production, Top10 system design và learning order](study-first.md). Bắt đầu theo [30-day plan](30-day-plan.md) hoặc [14-day crash plan](14-day-crash-plan.md), rồi [full mock115 phút](../23-mock-interview/full-mock-interview.md).
