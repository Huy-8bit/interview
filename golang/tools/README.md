# Kiểm tra giáo trình và các ví dụ

Chạy từ repository root. Reports và compiler/browser artifacts nằm trong `golang/.cache/`, được gitignore để không trộn với nội dung học. Những công cụ này kiểm tra cấu trúc và hành vi cụ thể; chúng không tự chứng minh mọi đoạn giải thích đúng hoặc đủ sâu.

```bash
python3 golang/tools/audit.py
python3 golang/tools/check-snippets.py
node golang/tools/check-mermaid.mjs /path/to/node_modules
```

### Giải thích lệnh và kết quả

Audit đọc toàn bộ Markdown, required paths, links/anchors và từng fenced block. Nó yêu cầu diagram có mục `Cách đọc diagram` ngay sau và code có walkthrough; bài lý thuyết không được dùng section ngân hàng câu hỏi. Snippets checker compile từng Go block trong harness độc lập, không chạy ví dụ cố ý race/leak. Mermaid checker dùng packages trong node_modules được cung cấp để parse sơ đồ; nó không tải package mới và không tương đương kiểm tra hình render trên mọi Markdown viewer.

## Phạm vi từng công cụ

`audit.py` phân loại lesson, guide và phụ lục. Nó kiểm tra bài nền tảng có độ dài tối thiểu như một tín hiệu review, sơ đồ có giải thích, system design có diễn tiến phiên bản và các đường lỗi có nội dung. Word count/heading không đo được chất lượng lập luận; người viết vẫn phải đọc ví dụ, ownership, assumptions và failure timeline. File `lesson-inventory.json` trong cache ghi từng bài để đối chiếu coverage.

`check-snippets.py` giữ nguyên các code blocks có package; snippets rời được bổ sung package/imports từ danh sách giới hạn và wrapper đã mô tả. Compile thành công không chứng minh output, no-leak hay database semantics. Các behavior tests nằm trong module examples và được chạy bằng race detector; một số complete programs còn có thể chạy kiểm tra output riêng trong đợt biên tập.

`check-mermaid.mjs` đọc diagram inventory từ audit rồi dùng Mermaid trong Chromium để kiểm tra syntax. Cần môi trường cho phép start browser process. Bản kiểm tra không cài dependencies, gọi partner services hay deploy hệ thống.

## Metadata và phạm vi filesystem

`required-files.json` giữ các paths đã yêu cầu; `catalog.json` giữ title/priority cho lộ trình, không còn yêu cầu 30 câu hỏi trong theory. `verification.json` ghi evidence của lượt kiểm tra cùng giới hạn thực tế. `python-baseline.json` là snapshot lịch sử chỉ để so sánh, không phải nguồn để restore bất cứ nội dung nào.

Có thể truyền `--python-baseline /path/to/snapshot.json` cho audit để so với một mốc khác đã chụp read-only. Drift chỉ nói files khác snapshot; công cụ không suy ai đã chỉnh sửa và không khôi phục Python. Toàn bộ công việc biên tập giáo trình này chỉ ghi dưới `golang/`.

[Báo cáo kiểm tra](../00-roadmap/repository-audit.md) · [Hướng dẫn labs](../examples/README.md)
