# Unit testing business contracts

## Bài toán và ví dụ đầu tiên

Một rule discount có nhiều boundary nhưng test chỉ happy path. Unit test kiểm tra behavior một phần nhỏ với input/dependency được kiểm soát, giúp lỗi được định vị mà không cần dựng toàn hệ thống.

## Đi từng bước qua một tình huống

Test quantity zero, ngưỡng discount, overflow policy và dependency error. Assert output/side effect thuộc contract, không assert mọi helper được gọi theo đúng thứ tự implementation nếu thứ tự đó không có nghĩa nghiệp vụ. Fake clock giúp test expiry không phải Sleep.

## Hiểu cơ chế từ kết quả quan sát

Isolation làm test nhanh nhưng fake có thể đơn giản hơn reality. Không dùng unit tests để khẳng định SQL isolation hoặc HTTP connection reuse; dành integration test đúng boundary. Table-driven test giúp chia sẻ cấu trúc khi các cases thật sự cùng behavior.

## Khái niệm và mô hình làm việc

Unit test giữ invariant và edge cases của function/package, không mirror từng line implementation.

## Cơ chế và những ranh giới cần giữ

Arrange inputs/dependencies explicit, deterministic clock/randomness khi cần; assert observable result/error classification. Test cleanup bằng done signals.

## Áp dụng vào hệ thống thật

Reserve inventory reject negative/oversell và preserve count on failure.

## Những đường lỗi cần hiểu

Tests chỉ happy path; sleep để chờ G; assert exact wrapped error string dễ brittle.

## Lần theo bằng chứng khi có sự cố

Run targeted test, go test ./..., -race cho concurrency; isolate shared globals.

## Đánh đổi và giới hạn sử dụng

Không mock mọi function; pure domain logic dùng real values.

## Thực hành, debugging và kết luận

Run test thường xuyên theo phạm vi đổi, dùng deterministic signals cho concurrency. Khi bug production xảy ra, viết case thể hiện invariant đã bị phá rồi sửa. Không thêm test chỉ lặp lại literal/config ít rủi ro mà không bảo vệ behavior có ý nghĩa.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

TestPoolCancellation dùng started channels để biết hai workers đã thực sự vào function rồi cancel. Done/error channel với timeout chỉ là failure bound, không là synchronization sleep. Sau RunPool return, active count phải0, chứng minh join. Test missing close trên input kèm worker error kiểm fail-fast siblings vẫn thoát; đây là invariant khó hơn chỉ count successful jobs.
