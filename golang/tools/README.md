# Documentation verification tools

Chạy từ repository root. Mọi report/cache output nằm trong `golang/.cache/` (được gitignore).

```bash
python3 golang/tools/audit.py
python3 golang/tools/check-snippets.py
node golang/tools/check-mermaid.mjs /path/to/node_modules
```

- `audit.py`: required paths, local Markdown links/anchors, fences, P0 sections/30-question structure, minimum review-depth flags,5 diagrams/design, exact duplicate documents, unfinished markers, question counts và Python baseline comparison. Nó cũng kiểm paragraphs dài trùng nguyên văn với Python hiện tại. Đây là structural audit, không là proof mọi technical statement đúng.
- `check-snippets.py`: compile20 Go code blocks; complete programs giữ nguyên, snippet harness bổ sung package/imports và supplied DB argument khi được document. Không chạy intentional leak/race snippets. `go test -race ./...` trong examples kiểm behavior của runnable labs.
- `check-mermaid.mjs`: dùng Mermaid và Puppeteer trong node_modules do caller cung cấp, parse các diagrams trích bởi audit. Không tự install/download packages hoặc gọi network. Chromium cần môi trường cho phép start process.
- `required-files.json`:276 paths từ yêu cầu ban đầu.
- `catalog.json`: title/priority metadata phục vụ P0 và dashboard coverage.
- `python-baseline.json`: SHA256/path snapshot lúc bắt đầu; chỉ dùng kiểm tra, không restore hay sửa Python.

Python có hoạt động chỉnh sửa ngoài task này trong khi xây tài liệu Golang. Audit báo drift dưới warnings thay vì sửa/khôi phục nội dung nằm ngoài scope. Không dùng baseline để kết luận author task này đã thay đổi Python.

[Audit report](../00-roadmap/repository-audit.md) · [Runnable labs](../examples/README.md)
