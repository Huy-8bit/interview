## Khái niệm và mô hình làm việc

## Bài toán và ví dụ đầu tiên

Giải thuật đúng bắt đầu từ input/output và assumptions. Một lời giải byte-based có thể đúng cho ASCII nhưng sai yêu cầu Unicode; một lời giải int có thể sai với overflow. Ghi contract trước làm reasoning và test có mục tiêu.

## Đi từng bước qua một tình huống

Lấy ví dụ lower-bound: input sorted, output có thể bằng len, không mutate input. Viết vài cases empty/duplicate/outside rồi invariant hai biên, mới code loop. Walkthrough bằng một input nhỏ chứng minh mỗi update giảm vùng và giữ đáp án.

## Hiểu cơ chế từ kết quả quan sát

Trong Go cần phân biệt nil/empty, slice alias, map comma-ok và pointer ownership. Tránh generic abstraction nếu nó làm bài nhỏ khó đọc; dùng helper khi nó biểu đạt một subproblem có contract. Complexity phải tính result storage và input copy, không chỉ biến local.

Clarify input domain, mutation, nil/empty, overflow và ordering trước code.

## Cơ chế và những ranh giới cần giữ

State invariant và complexity, viết simplest correct algorithm, dry-run edge cases, rồi optimize nếu constraint đòi. Go map/slice ownership và cleanup là một phần answer.

## Áp dụng vào hệ thống thật

Parser/worker interview cần context và bounded resources, không chỉ algorithm happy path.

## Những đường lỗi cần hiểu

Code compile nhưng ignores error; int overflow; solution sửa input dù contract cấm.

## Lần theo bằng chứng khi có sự cố

Run examples tests, race cho concurrency và fuzz invariant; đọc failing minimal input.

## Đánh đổi và giới hạn sử dụng

Không dùng clever unsafe hoặc generic abstraction để che logic bài nhỏ.

## Thực hành, debugging và kết luận

Chạy examples/algorithms_test.go để xem edge/property tests. Khi tối ưu, giữ reference/invariant độc lập với implementation để test không lặp bug. Giải thích giới hạn rõ rồi mở rộng nếu yêu cầu đổi; không ngầm hứa Unicode/cycle/overflow support mà code chưa có.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
