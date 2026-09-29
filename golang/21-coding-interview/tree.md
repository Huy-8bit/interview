# Tree traversal và depth

## Bài toán và ví dụ đầu tiên

Inorder traversal đi trái, node, phải. Recursion ngắn nhưng cây rất sâu có thể tạo nhiều call frames. Dùng stack explicit giúp thấy rõ những node đang đợi được thăm.

## Đi từng bước qua một tình huống

Với root 2 có left 1,right 3, đẩy 2 rồi 1 vào stack khi đi trái. Không còn left thì pop 1 và ghi result, chuyển right của 1 là nil; pop 2, ghi 2 rồi chuyển sang 3; đẩy/pop 3 và ghi 3. Kết quả 1,2,3; thứ tự tăng chỉ được bảo đảm nếu input là BST đúng invariant.

## Hiểu cơ chế từ kết quả quan sát

Stack giữ tổ tiên chưa được visit. Mỗi node push/pop một lần nên O(n), extra stack O(h) với h là chiều cao, result O(n). Sau pop, lab xóa pointer trong slot trước reslice để không giữ node không cần. Input graph có cycle không là tree theo contract này.

## Khái niệm và mô hình làm việc

Inorder binary tree là left,node,right; với BST hợp lệ kết quả sorted theo invariant.

## Cơ chế và những ranh giới cần giữ

Iterative stack tránh recursion depth lớn; each node push/pop một lần O(n), auxiliary O(height). Clear popped pointers nếu stack giữ backing array lâu.

## Áp dụng vào hệ thống thật

Nested config/AST traversal cần bound depth và detect cycle nếu structure không bảo đảm tree.

## Những đường lỗi cần hiểu

Assume mọi binary tree là BST; skewed tree recursion làm stack growth lớn.

## Lần theo bằng chứng khi có sự cố

Test empty, balanced, skewed và duplicate-key policy; verify traversal order độc lập.

## Đánh đổi và giới hạn sử dụng

Recursive code dễ đọc cho bounded depth; iterative dễ kiểm memory/cancellation.

## Thực hành, debugging và kết luận

Test nil tree, skewed tree và tree không BST để không nhầm traversal với sort. Với dữ liệu untrusted, cần depth/node bound hoặc cycle validation theo API. Explicit stack làm resource dễ thấy nhưng không tự giới hạn tổng input.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
