# Graph BFS và visited timing

## Bài toán và ví dụ đầu tiên

Cần tìm số cạnh ít nhất từ một node tới các node khác trong graph không trọng số. Breadth-first search, viết tắt BFS, mở rộng từng lớp khoảng cách nên lần đầu gặp node là khoảng cách ngắn nhất theo số cạnh.

## Đi từng bước qua một tình huống

Graph0 nối 1,2;1 nối 3;2 cũng nối 3. Queue bắt đầu0 với distance0. Pop0, đánh dấu 1 và 2 distance 1 ngay khi enqueue. Pop 1, thêm 3 distance 2. Pop 2 thấy 3 đã được đánh dấu nên không enqueue lại. Nếu đợi tới lúc pop mới mark, cùng node có thể bị thêm nhiều lần.

## Hiểu cơ chế từ kết quả quan sát

Map distance đồng thời là visited set. Queue giữ thứ tự theo lớp, adjacency lists biểu diễn edges. Time O(V+E) cho phần reachable theo representation, memory O(V). Nếu cạnh có trọng số khác nhau, BFS không bảo đảm shortest weighted path; cần thuật toán phù hợp như Dijkstra với assumptions của nó.

## Khái niệm và mô hình làm việc

BFS tìm shortest edge-count paths trong unweighted graph; weighted graph cần thuật toán khác.

## Cơ chế và những ranh giới cần giữ

Mark visited khi enqueue để mỗi vertex vào queue một lần; distance[next]=distance[v]+1. O(V+E), map adjacency traversal order không deterministic nếu iterate map.

## Áp dụng vào hệ thống thật

Dependency reachability và shortest hop count; real network latency không là edge-count distance.

## Những đường lỗi cần hiểu

Mark lúc dequeue enqueue duplicates; cycles không visited vô hạn; disconnected vertices bị assume reachable.

## Lần theo bằng chứng khi có sự cố

Test cycle, self-loop, disconnected node và multiple shortest paths; compare distances thay exact traversal order.

## Đánh đổi và giới hạn sử dụng

Dijkstra cho nonnegative weights; DFS phù hợp reachability/topological work với cycle checks.

## Thực hành, debugging và kết luận

Test cycle, disconnected nodes, start không có adjacency và duplicate edges. Chỉ trả distance cho reachable nodes theo lab contract. Với graph rất lớn, traversal cần budget/cancellation và storage strategy; O(V+E) vẫn có thể vượt memory dù complexity tối ưu theo mô hình nhỏ.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
