# CPU profile: execution cost

## Bài toán và ví dụ đầu tiên

CPU tăng nhưng chưa biết code nào tiêu tài nguyên. CPU profile lấy mẫu stack khi process thực thi CPU, giúp xếp chi phí theo function/caller trong một cửa sổ workload.

## Đi từng bước qua một tình huống

Nếu 60% samples nằm trong parsing, tối ưu connection pool không nhắm đúng phần CPU này. Xem flat rồi cumulative để phân biệt function tự làm nhiều việc và wrapper gọi nhiều callee đắt. List source giúp nối sample với vòng lặp hoặc allocation cụ thể.

## Hiểu cơ chế từ kết quả quan sát

Profile không đo đầy đủ thời gian waiting; goroutine chờ DB 2 giây có thể đóng góp ít CPU sample. Sampling noise làm phần trăm nhỏ không ổn định, và profile dưới tải khác không so trực tiếp được. Race/trace/debug flags còn đổi overhead.

## Khái niệm và mô hình làm việc

CPU samples cho execution đang tiêu CPU, không toàn request wall time.

## Cơ chế và những ranh giới cần giữ

top tìm flat cost; top -cum và list tìm callers/lines; look for JSON, regex, compression, busy loops, GC assist.

## Áp dụng vào hệ thống thật

Capture 30s khi CPU95%, RPS normal và latency cao, giữ deployment build ID.

## Những đường lỗi cần hiểu

Chỉ nhìn runtime.mallocgc mà bỏ caller tạo allocations; CPU throttle khiến wall time tăng nhưng profile không toàn bức tranh.

## Lần theo bằng chứng khi có sự cố

Correlate profile với CPU quota/throttled time và offered load.

## Đánh đổi và giới hạn sử dụng

Không tối ưu cold functions vì graph trông lớn; quantify percent contribution.

## Thực hành, debugging và kết luận

Thu cửa sổ có symptom, ghi RPS/payload/quota và build ID. So canary/baseline rồi thay một hot path có hypothesis. Xác nhận correctness và P99 sau tối ưu, vì giảm CPU bằng cache có thể thêm stale data hoặc retained memory.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
