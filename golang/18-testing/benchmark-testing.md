# Benchmark tests có statistical comparison

## Bài toán và ví dụ đầu tiên

Một thay đổi code được cho là giảm allocation cần bằng chứng mà test correctness không cung cấp. Benchmark test đo operation lặp với input đại diện; correctness tests vẫn cần riêng để bảo đảm bản nhanh hơn trả kết quả đúng.

## Đi từng bước qua một tình huống

Chuẩn bị fixture phù hợp, không tính setup không thuộc operation trừ khi production cũng chịu setup đó. Giữ output để compiler không bỏ work, dùng -benchmem để đọc allocation và chạy đủ mẫu để nhìn noise. Benchmark parallel cần state concurrency giống production.

## Hiểu cơ chế từ kết quả quan sát

Một số optimization được compiler áp khi input constant nhỏ nhưng mất ở service thật; test nhiều sizes/distributions. CPU quota, toolchain và profiler flags đổi kết quả. Giảm ns/op mà tăng tail latency do lock contention có thể không đáp ứng mục tiêu.

## Khái niệm và mô hình làm việc

Benchmark kết quả phải repeatable và dùng đúng input distribution.

## Cơ chế và những ranh giới cần giữ

b.ReportAllocs, setup ngoài measured loop theo API, consume result để compiler không loại. Run multiple samples rồi benchstat.

## Áp dụng vào hệ thống thật

BenchmarkFormat trong examples là harness nhỏ; thêm payload distribution trước suy production benefit.

## Những đường lỗi cần hiểu

Parallel benchmark vượt downstream thật giả lập; global sink tạo shared race nếu RunParallel.

## Lần theo bằng chứng khi có sự cố

Compare ns/op, bytes/allocs và profile on same build; report hardware/toolchain.

## Đánh đổi và giới hạn sử dụng

Không fail CI theo threshold quá nhạy nếu runners noisy; controlled perf lane tốt hơn.

## Thực hành, debugging và kết luận

Ghi command/build/workload khi so before-after. Dùng load test bổ sung cho network/pool behavior. Không biến con số một lần trên laptop thành SLA; báo assumptions và phạm vi kết luận.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

Thử BenchmarkFormat với nhiều count, lưu before/after và benchstat khi tool sẵn có. Nếu đổi benchmark sang RunParallel, global string sink sẽ trở thành data race; dùng goroutine-local consumption hoặc design sink đúng contract. Benchmark config phải ghi GOMAXPROCS, toolchain và input sizes. Performance comparison chỉ hợp khi work và result semantics giữ nguyên.
