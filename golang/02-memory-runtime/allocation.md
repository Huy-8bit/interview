# Allocation rate và allocator

## Bài toán và ví dụ đầu tiên

API parse mỗi request thành nhiều struct tạm. Heap sau GC vẫn nhỏ nhưng CPU dành cho GC cao. Allocation rate đo lượng byte/object mới tạo theo thời gian; nó khác lượng memory còn sống, nên chỉ nhìn RSS có thể bỏ qua chi phí này.

## Đi từng bước qua một tình huống

Nếu mỗi request tạo 50 KB và có 10000 request/s, tốc độ cấp phát xấp xỉ 500 MB/s trước overhead. Giảm còn 25 KB/request có thể giảm áp lực GC dù peak live data không đổi nhiều. Khi so benchmark, B/op là byte mỗi operation và allocs/op là số allocation, không phải byte mỗi giây.

## Hiểu cơ chế từ kết quả quan sát

Allocator chia kích thước thành các nhóm và dùng cấu trúc cache cục bộ để giảm tranh chấp. Pointer density ảnh hưởng lượng dữ liệu GC cần scan; hai buffer cùng byte size nhưng một bên nhiều pointer có thể có chi phí khác. Chi tiết mcache/mcentral/mheap thuộc implementation phiên bản cụ thể.

## Khái niệm và mô hình làm việc

Allocation rate là bytes/objects tạo mỗi giây; live heap là objects còn reachable sau collection.

## Cơ chế và những ranh giới cần giữ

Allocator phân size classes và có local caching; exact mcache/mcentral/mheap là implementation detail. Tiny objects, pointer density và zeroing ảnh hưởng chi phí.

## Áp dụng vào hệ thống thật

Giảm temporary string/byte conversions trong hot serialization path sau profiling.

## Những đường lỗi cần hiểu

Pool giữ buffer cực lớn sau một request; benchmark không giữ result nên compiler loại work.

## Lần theo bằng chứng khi có sự cố

So alloc_space, alloc_objects, B/op và allocs/op; cùng RPS mới so rate.

## Đánh đổi và giới hạn sử dụng

Preallocate có ích khi size biết rõ; cap buffer pooled để tránh giữ outlier.

## Thực hành, debugging và kết luận

Profile alloc_space để tìm tổng allocation nóng, rồi xem list/caller để xác định conversion hay temporary object. Giữ kết quả benchmark tránh compiler loại công việc. Pool chỉ có ích khi reuse đúng lifetime; giữ buffer peak cực lớn có thể đổi giảm churn thành tăng retained memory.


## Đọc tiếp

- [Garbage collection: live heap, pacing và memory budget](garbage-collector.md)
- [Escape analysis: đọc quyết định của compiler](escape-analysis.md)
- [memory-profile](../16-performance/memory-profile.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/gc-guide)
