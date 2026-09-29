# Execution trace: timeline scheduling

## Bài toán và ví dụ đầu tiên

CPU profile thấp nhưng user chờ lâu vì goroutine runnable chưa được chạy hoặc bị park ở network. Execution trace ghi timeline sự kiện runtime để nối trạng thái goroutine, scheduling và blocking.

## Đi từng bước qua một tình huống

Thu trace ngắn của workload có symptom rồi xem goroutine từ waiting sang runnable và running. Khoảng waiting gắn với sự kiện cần chờ; khoảng runnable là đã sẵn sàng nhưng chưa được CPU phục vụ. Đừng cộng mọi khoảng thành “scheduler chậm” nếu phần lớn là dependency chưa ready.

## Hiểu cơ chế từ kết quả quan sát

Trace có overhead và lượng dữ liệu lớn nên giới hạn thời gian/phạm vi. User regions/tasks có thể gắn operation ứng dụng với runtime timeline khi được instrument. Binary/version và workload metadata giúp đọc đúng vì UI/event chi tiết đổi theo toolchain.

## Khái niệm và mô hình làm việc

Trace cho lịch G, network/syscall blocking, GC và runtime events theo thời gian.

## Cơ chế và những ranh giới cần giữ

go test -trace trace.out rồi go tool trace; inspect runnable delay, processor utilization và task regions. Runtime trace APIs có thể annotate business task với context.

## Áp dụng vào hệ thống thật

Latency burst dù mean CPU thấp: tìm runnable queue sau quota throttling hoặc fan-out wake storm.

## Những đường lỗi cần hiểu

Trace quá dài phình storage/overhead; chỉ nhìn timeline không correlate request IDs.

## Lần theo bằng chứng khi có sự cố

Chọn cửa sổ ngắn bao regression; compare scheduler delay với dependency spans.

## Đánh đổi và giới hạn sử dụng

Profile tốt cho aggregate hotspots, trace tốt cho causality/timing; dùng cả khi cần.

## Thực hành, debugging và kết luận

Dùng lab go test -trace để học trước, rồi thu production có kiểm soát. Đối chiếu CPU quota, pool metrics và distributed spans để giải thích nguyên nhân. Trace cho bằng chứng timeline, không tự quyết định tăng GOMAXPROCS hay thêm worker là đúng.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
