# Context từ request bị bỏ dở tới cleanup

Đọc context-basics trước cancellation, rồi timeout/deadline và propagation. Trọng tâm là ba việc khác nhau: phát tín hiệu dừng, công việc quan sát tín hiệu rồi return, và owner chờ cleanup hoàn tất. Ví dụ HTTP→service→DB giúp thấy context phải đi tới thao tác cuối chứ không chỉ có trong chữ ký hàm.

## Bắt đầu và cách thực hành

Bắt đầu với [context-basics](context-basics.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Cancellation propagation](cancellation.md) | P1 |
| [Context mistakes thường gặp](common-mistakes.md) | P1 |
| [Context: cây lifetime và cooperative cancellation](context-basics.md) | P0 |
| [Context values có scope](context-values.md) | P1 |
| [Context trong production request tree](production-patterns.md) | P1 |
| [Propagation qua process boundary](propagation.md) | P1 |
| [Timeout và deadline budget](timeout-deadline.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
