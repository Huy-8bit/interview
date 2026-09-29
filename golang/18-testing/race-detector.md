# Race detector workflow

## Bài toán và ví dụ đầu tiên

Concurrent code có thể chạy đúng nhiều lần rồi hỏng khi scheduler chọn interleaving khác. Race detector instrument memory accesses và synchronization trong những đường test thực sự chạy để phát hiện data races.

## Đi từng bước qua một tình huống

Chạy go test -race trên package có shared state. Báo cáo gồm access stacks và nơi goroutine được tạo; tìm cả reader lẫn writer, rồi bảo vệ invariant bằng cùng protocol. Chỉ lock dòng được báo ở một phía có thể còn access khác không được đồng bộ.

## Hiểu cơ chế từ kết quả quan sát

Không có report chưa chứng minh không có race ở path chưa chạy. Race detector cũng không phát hiện mọi race condition nghiệp vụ như double booking qua hai DB transactions. Nó có overhead đáng kể, nên số benchmark -race không so trực tiếp với build thường.

## Khái niệm và mô hình làm việc

go test -race ./... instrument executed paths để phát hiện conflicting memory access thiếu synchronization.

## Cơ chế và những ranh giới cần giữ

Report gồm access stacks và G creation; fix ownership/happens-before, rerun workload. Không phát hiện mọi distributed logical race.

## Áp dụng vào hệ thống thật

Negative lab build tag racedemo phải fail; default suite phải pass race.

## Những đường lỗi cần hiểu

Empty coverage tạo false confidence; timing under instrumentation làm bug path biến đổi.

## Lần theo bằng chứng khi có sự cố

Exercise shared paths với realistic concurrency; inspect both stacks, run vet copylocks.

## Đánh đổi và giới hạn sử dụng

Race overhead cao; staging/targeted canary cần budget; không substitute code reasoning.

## Thực hành, debugging và kết luận

Lab racedemo được tách build tag vì cố ý fail. Test bình thường cần ép error/cancel/close paths với channel coordination. Sau sửa, chạy race test có ý nghĩa và integration test invariant durable nếu vấn đề ở nhiều process.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

Negative example được tách bằng build tag racedemo. Lệnh `go test -race -tags racedemo -run TestIntentionalRace` phải nonzero và chứa DATA RACE; default `go test -race ./...` phải pass. Nhờ tách tag, một expected failure không làm suite thường luôn đỏ. Fix increment bằng atomic/lock rồi compare report, nhưng nhớ logical duplicate test vẫn riêng.
