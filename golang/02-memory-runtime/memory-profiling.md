# Memory profiling: retained versus allocated

## Bài toán và ví dụ đầu tiên

Một team nhìn alloc_space lớn rồi kết luận memory leak. alloc_space cộng dồn allocation được lấy mẫu, nên tăng theo lượng công việc ngay cả khi object chết nhanh. inuse_space tập trung memory còn giữ ở thời điểm lấy profile và trả lời câu hỏi khác.

## Đi từng bước qua một tình huống

Lấy hai heap profiles cách nhau trong workload ổn định, chọn cùng sample_index để so. Nếu cumulative allocation tăng nhanh nhưng retained heap sau GC gần như ổn định, ưu tiên giảm churn. Nếu retained objects tăng theo thời gian sau khi traffic đã về baseline, tìm ownership dài hạn hoặc queue không drain.

## Hiểu cơ chế từ kết quả quan sát

Pprof dùng sampling nên số nhỏ có sai số và không phải mọi allocation đều có record. Build ID và binary tương ứng giúp map địa chỉ về đúng source. Ép GC trước profile có thể làm phép so retained data dễ hơn nhưng thay đổi state và tạo overhead; ghi rõ điều kiện lấy mẫu.

## Khái niệm và mô hình làm việc

Heap/inuse cho memory còn sống; alloc_space cho cumulative churn theo samples.

## Cơ chế và những ranh giới cần giữ

go tool pprof -sample_index=inuse_space hoặc alloc_space đổi câu hỏi, không đổi workload. Forced GC có thể giúp so retained set nhưng gây overhead và thay state.

## Áp dụng vào hệ thống thật

So baseline/canary cùng input và uptime; ghi build ID để symbolization đúng.

## Những đường lỗi cần hiểu

Nhìn alloc_space rồi kết luận leak; RSS tăng do mmap/cgo mà heap profile không giải thích.

## Lần theo bằng chứng khi có sự cố

Xem top, top -cum, list và caller graph; chia rate theo elapsed time/RPS.

## Đánh đổi và giới hạn sử dụng

Profile sampling có sai số với allocations nhỏ; không suy exact object count từ sample đơn.

## Thực hành, debugging và kết luận

Xem top để tìm hàm nổi bật, top -cum và graph để biết caller dẫn tới đó. Nếu RSS tăng mà Go heap không giải thích, kiểm tra cgo/mmap, stack và runtime/system accounting. Không tune GC chỉ vì một snapshot; cần trend, workload và tác động latency cùng thời điểm.


## Đọc tiếp

- [Garbage collection: live heap, pacing và memory budget](garbage-collector.md)
- [Escape analysis: đọc quyết định của compiler](escape-analysis.md)
- [memory-profile](../16-performance/memory-profile.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/gc-guide)
