# Benchmark đúng workload

## Bài toán và ví dụ đầu tiên

Hai implementation cùng đúng nhưng chưa biết cách nào phù hợp hot path. Benchmark đo chi phí dưới một workload xác định; nó không tự đại diện toàn production.

## Đi từng bước qua một tình huống

Tạo input có size/distribution giống route cần tối ưu, chuẩn bị phần không thuộc operation ngoài timer khi phù hợp, giữ result để compiler không bỏ work. Đọc ns/op, B/op và allocs/op cùng nhau. Parallel benchmark chỉ có ý nghĩa khi shared state/contention giống cách dùng thật.

## Hiểu cơ chế từ kết quả quan sát

Warm caches, CPU scaling, Go version, GOMAXPROCS và background load ảnh hưởng số đo. Một thay đổi nhỏ hơn noise cần nhiều mẫu và công cụ so thống kê phù hợp; một benchmark input 10 items không suy ra behavior 1 triệu items.

## Khái niệm và mô hình làm việc

Benchmark phải đo operation cần tối ưu, có input đại diện và compiler không loại toàn work.

## Cơ chế và những ranh giới cần giữ

go test -run ^$ -bench . -benchmem -count=10; tách setup khỏi timer khi phù hợp; sink result có thể thay escape nên chọn tương ứng caller.

## Áp dụng vào hệ thống thật

So before/after cùng CPU/toolchain, nhiều payload sizes và hot/cold distributions.

## Những đường lỗi cần hiểu

Một run bị thermal/noisy neighbor; benchmarking allocations của fmt thay code chính.

## Lần theo bằng chứng khi có sự cố

Xem ns/op, B/op, allocs/op và benchstat confidence; profile benchmark chỉ để đặt giả thuyết.

## Đánh đổi và giới hạn sử dụng

Microbench không thay load test end-to-end/P99; giữ correctness tests.

## Thực hành, debugging và kết luận

Ghi command/environment, so cùng workload và kiểm tra correctness trước. Sau microbenchmark, dùng integration/load test cho pool/network/queue. Không dùng con số lab làm cam kết capacity production; đưa giả định cùng số liệu để người đọc đánh giá được phạm vi.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
