# Heap và allocs profiles

## Bài toán và ví dụ đầu tiên

RSS tăng khiến team muốn biết bộ nhớ nào còn sống. Heap profile lấy mẫu allocations của Go để nhìn retained memory hoặc tổng allocation; nó không bao phủ mọi memory ngoài Go runtime.

## Đi từng bước qua một tình huống

Chọn inuse_space để tìm bytes còn giữ, inuse_objects để tìm nhiều object nhỏ, alloc_space để xem churn. Cùng profile đổi sample_index có thể đổi hoàn toàn top functions. Một allocation site đứng đầu cho biết nơi tạo object, chưa luôn chỉ ra reference nào giữ nó sống.

## Hiểu cơ chế từ kết quả quan sát

GC timing và sampling ảnh hưởng snapshot. Forced GC có thể hỗ trợ phép so retained set nhưng có overhead và đổi state; ghi rõ điều kiện. RSS gồm stack, runtime, mapped/native memory và memory chưa trả OS, nên profile heap thấp không bác bỏ mọi pressure container.

## Khái niệm và mô hình làm việc

inuse_space cho retained bytes; alloc_space cho allocation volume sampled từ lịch sử profile.

## Cơ chế và những ranh giới cần giữ

Use sample_index để đổi views, diff cùng steady state; forced GC ảnh hưởng state và latency nên có chủ đích.

## Áp dụng vào hệ thống thật

Cache token giữ huge backing array thấy allocation site của original payload.

## Những đường lỗi cần hiểu

Confuse alloc_space với leak; RSS ngoài Go do cgo/mmap không hiện đầy đủ.

## Lần theo bằng chứng khi có sự cố

So inuse_objects/space, goroutine stacks và cache cardinality qua thời gian.

## Đánh đổi và giới hạn sử dụng

Giảm memory bằng clone có thể tăng allocs nhưng giảm retention; measure cả hai.

## Thực hành, debugging và kết luận

So hai thời điểm workload/uptime có ý nghĩa và đọc cache/queue/goroutine ownership. Sửa một retention path rồi xác minh live heap sau drain giảm; đừng chỉ nhìn allocs/op khi vấn đề là cache không bound.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)

## Thực hành có điều kiện kiểm chứng

Chạy benchmark với `-memprofile=mem.out`, mở lần lượt `go tool pprof -sample_index=alloc_space mem.out` và `-sample_index=inuse_space`. Format benchmark tạo short-lived strings nên two views khác nhau là hợp lý. Để đo retention, cần workload giữ references có chủ đích; không suy parser leak từ benchmark này. Ghi capture uptime/RPS để cumulative profiles so được.
