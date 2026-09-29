# Top K với min-heap

## Bài toán và ví dụ đầu tiên

Muốn giữ k giá trị lớn nhất trong một luồng mà không sort toàn bộ n phần tử. Min-heap kích thước k giữ phần tử nhỏ nhất trong nhóm ứng viên ở root, giúp biết khi nào số mới xứng đáng thay thế.

## Đi từng bước qua một tình huống

Với [5,1,9,3], k2: push5 rồi1, root1. Gặp9 lớn hơn1 thì thay root và heap.Fix, heap giữ5,9. Gặp3 nhỏ hơn root5 thì bỏ. Pop lần lượt min từ heap cho output5,9 như contract TopK của lab.

## Hiểu cơ chế từ kết quả quan sát

Heap invariant chỉ bảo đảm parent theo thứ tự với children, không có nghĩa backing slice đã sort. container/heap gọi các methods Len/Less/Swap/Push/Pop; method Pop của type lấy phần tử cuối theo protocol package sau khi heap đã sắp xếp thích hợp, không tự là thao tác lấy root hoàn chỉnh.

## Khái niệm và mô hình làm việc

Heap size K giữ K largest seen; root là nhỏ nhất trong selected set, dễ loại khi gặp value lớn hơn.

## Cơ chế và những ranh giới cần giữ

O(n log K) time/O(K) memory; container/heap yêu cầu Len/Less/Swap và pointer Push/Pop. Fix root sau replace, output heap pop ascending theo implementation example.

## Áp dụng vào hệ thống thật

Top metrics trong bounded batch; streaming top-K cần define window/expiry khác static input.

## Những đường lỗi cần hiểu

Nhầm min/max orientation; K0 index panic; returning heap array tưởng sorted.

## Lần theo bằng chứng khi có sự cố

Test duplicates, negative values, K0/K>n và order của output; benchmark K nhỏ/lớn.

## Đánh đổi và giới hạn sử dụng

Sort O(n log n) đơn giản nếu cần full ordered result; quickselect đổi worst-case/stability.

## Thực hành, debugging và kết luận

Time khoảng O(n log k) và storage O(k), duplicates được giữ theo bài. Validate k<0 hoặc k>n thành lỗi, k0 trả empty. Nếu k gần n và cần toàn bộ sorted output, sort có thể đơn giản/nhanh hơn; benchmark workload và ghi rõ output order.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/container/heap)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
