# Linked list reversal

## Bài toán và ví dụ đầu tiên

Đảo list 1→2→3 cần đổi hướng Next mà không mất đường tới phần chưa xử lý. Mỗi node chỉ biết node tiếp theo, nên thứ tự gán pointer quyết định có giữ được toàn bộ list hay không.

## Đi từng bước qua một tình huống

Bắt đầu prev=nil, head=1. Lưu next=2 trước, đặt1.Next=nil, rồi prev=1,head=2. Vòng sau lưu3, đặt2.Next=1, dịch prev/head. Cuối cùng head=nil và prev=3 là đầu mới3→2→1. Nếu đổi Next trước khi lưu next, phần đuôi có thể mất khỏi traversal.

## Hiểu cơ chế từ kết quả quan sát

Invariant: prev là list đã đảo, head là đầu phần chưa xử lý. Mỗi vòng chuyển đúng một node, nên O(n) time và O(1) extra memory. Algorithm mutate links của input; caller còn alias tới nodes sẽ thấy cấu trúc thay đổi. Input cyclic không thỏa contract list kết thúc bằng nil.

## Khái niệm và mô hình làm việc

Reversal cập nhật next pointers in-place, giữ reference phần chưa xử lý trước khi đổi link.

## Cơ chế và những ranh giới cần giữ

Invariant prev là reversed prefix, head là suffix chưa xử lý. Mỗi bước next=head.Next, head.Next=prev rồi tiến hai pointers. O(n) time/O(1) auxiliary space.

## Áp dụng vào hệ thống thật

Bài luyện pointer ownership; intrusive structures production còn cần concurrency/lifetime protocol.

## Những đường lỗi cần hiểu

Mất next tạo đứt list; cycle input khiến loop vô hạn; aliases nhìn thấy mutation.

## Lần theo bằng chứng khi có sự cố

Test nil/single/two nodes và verify tail.Next=nil, node identity giữ nguyên.

## Đánh đổi và giới hạn sử dụng

Slice thường cache-friendly hơn list; không chọn linked list chỉ vì insert O(1) nếu chưa có node pointer.

## Thực hành, debugging và kết luận

Test nil, single node và nhiều node, kiểm tra cả values lẫn liên kết/cycle. Nếu cần immutable list phải copy nodes và chấp nhận O(n) storage. Trong Go, GC không thay việc giữ pointer đúng lúc; mất reference tới đuôi vẫn là lỗi logic dù không gây use-after-free.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
