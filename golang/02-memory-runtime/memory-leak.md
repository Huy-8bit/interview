# Memory leak trong ngôn ngữ có GC

## Bài toán và ví dụ đầu tiên

Memory tăng không ngừng dù chương trình có GC khiến nhiều người nghi collector hỏng. Thường object vẫn còn reachable từ cache, queue, closure hoặc goroutine mà ứng dụng quên giải phóng. GC làm đúng việc giữ object còn có đường tham chiếu.

## Đi từng bước qua một tình huống

Một cache map[userID]*Profile không có eviction tăng theo số user từng xuất hiện. TTL chỉ hữu ích nếu entry thực sự được xóa hoặc cơ chế lookup/cleanup giới hạn retention; field expiresAt tự nó không loại entry khỏi map. Một slice nhỏ giữ một array lớn cũng có thể làm live heap cao hơn dữ liệu hữu ích.

## Hiểu cơ chế từ kết quả quan sát

Heap profile chỉ ra allocation site của object được lấy mẫu, không tự dựng đầy đủ mọi retaining path. Cần đọc code từ nơi allocate đến nơi giữ lâu dài, đối chiếu goroutine stack và cardinality của cache/metrics. RSS còn gồm phần ngoài heap Go và memory chưa trả OS nên không thể đồng nhất mọi RSS growth với leak.

## Khái niệm và mô hình làm việc

Leak thường là reference vẫn reachable nhưng không còn business value: cache, slice, closure hoặc goroutine bị quên.

## Cơ chế và những ranh giới cần giữ

GC không biết entry cache đã hết ý nghĩa. Heap profile cho allocation site, không trực tiếp cho mọi retaining path như một object graph debugger.

## Áp dụng vào hệ thống thật

Cache có max entries/bytes, TTL và eviction; worker queue có bound trên cả count và payload size.

## Những đường lỗi cần hiểu

Ticker worker giữ ctx cũ; giant array qua sub-slice; metrics label theo request ID giữ state vô hạn.

## Lần theo bằng chứng khi có sự cố

Lấy profiles cùng tải cách nhau nhiều phút, so inuse_space và inuse_objects; đối chiếu goroutine count/cardinality.

## Đánh đổi và giới hạn sử dụng

TTL đơn thuần không bound burst memory; thêm size limit và admission.

## Thực hành, debugging và kết luận

Lấy profile sau các chu kỳ tải tương đương và cùng điều kiện GC/uptime, xem retained set có tăng không. Thử drain traffic để phân biệt in-flight hợp lệ với state không giảm. Sửa bằng bound, eviction hoặc lifecycle; restart chỉ là mitigation và có thể tạo cold-cache load khi quay lại.


## Đọc tiếp

- [Garbage collection: live heap, pacing và memory budget](garbage-collector.md)
- [Escape analysis: đọc quyết định của compiler](escape-analysis.md)
- [memory-profile](../16-performance/memory-profile.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/gc-guide)
