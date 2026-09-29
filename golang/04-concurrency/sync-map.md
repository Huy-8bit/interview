# sync.Map versus typed map

## Bài toán và ví dụ đầu tiên

Một registry lưu kết quả tính một lần theo key rồi đọc nhiều lần. Native map cần đồng bộ nếu có write đồng thời; sync.Map cung cấp operation concurrent có sẵn. Nó là công cụ cho workload phù hợp, không làm mọi invariant liên quan map tự đúng.

## Đi từng bước qua một tình huống

Hai goroutine cùng Load thấy key chưa có, cùng tính object rồi Store. Nếu cần chỉ một object được chọn, LoadOrStore thực hiện chọn atomically. Nhưng đối số đã được tính trước khi call, nên expensiveBuild vẫn có thể chạy hai lần. Nếu chỉ được phép thực hiện side effect một lần, cần điều phối việc tính chứ không chỉ việc lưu.

## Hiểu cơ chế từ kết quả quan sát

Value chứa pointer vẫn có state mutable cần bảo vệ riêng. Range không phải snapshot nhất quán của toàn map tại một thời điểm: các key có thể phản ánh những thời điểm khác nhau. Không dùng Range để kết luận tổng balance chính xác dưới concurrent writes. Internal implementation có thể đổi qua release; lựa chọn dựa contract và benchmark workload.

## Khái niệm và mô hình làm việc

sync.Map tối ưu một số concurrent-key workloads; native map + lock thường dễ giữ type/invariant hơn.

## Cơ chế và những ranh giới cần giữ

Dùng LoadOrStore cho atomic initialization, nhưng compute argument trước call vẫn có thể chạy nhiều lần. Range không phải consistent snapshot. Internals thay đổi theo Go release, không dựa mô hình read/dirty cũ như luật.

## Áp dụng vào hệ thống thật

Registry write-once/read-many hoặc independent-key state sau benchmark.

## Những đường lỗi cần hiểu

Load rồi Store tạo lost update; values chứa pointer vẫn race; Range bị dùng làm transactional snapshot.

## Lần theo bằng chứng khi có sự cố

Đo hit rate/churn/contention; test compound operations và use-after-delete logic.

## Đánh đổi và giới hạn sử dụng

Không chọn sync.Map cho invariant nhiều keys hoặc khi cần type safety đơn giản.

## Thực hành, debugging và kết luận

Bắt đầu từ map có kiểu và mutex nếu nhiều key phải cập nhật cùng nhau. So sánh workload write-once/read-many, key churn và hot key trên đúng Go version. Race test phải truy cập object bên trong value, không chỉ gọi Load/Store; contention thấp của container không chứng minh payload an toàn.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
