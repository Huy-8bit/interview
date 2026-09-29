# Ordering và contiguous commit

## Bài toán và ví dụ đầu tiên

Consumer nhận event order-created rồi order-cancelled theo đúng log nhưng dispatch hai goroutine; cancel xử lý nhanh hơn create. Broker order không tự trở thành thứ tự hoàn tất side effect khi application song song hóa.

## Đi từng bước qua một tình huống

Với state cần theo order ID, xử lý tuần tự theo key hoặc dùng version/sequence trong DB để từ chối update cũ. Nếu version 12 đến trước 11, policy phải biết chờ gap, fetch snapshot hay áp event có thể giao hoán; không âm thầm overwrite bằng thứ tự arrival bất kỳ.

## Hiểu cơ chế từ kết quả quan sát

Global order giảm parallelism và thường không cần cho mọi entity. Per-key order giữ invariant ở phạm vi nhỏ hơn nhưng hot key vẫn serialize. Retry/DLQ có thể bỏ record lỗi ra khỏi dòng chính; events sau có được tiếp tục hay không là quyết định semantics.

## Khái niệm và mô hình làm việc

Broker order không bảo đảm side-effect completion order khi consumer chạy parallel.

## Cơ chế và những ranh giới cần giữ

Offsets 10,11,12: nếu 12 xong trước 10, không commit tiến qua 10 chưa xong. Commit offset biểu thị next record theo client/protocol contract; track contiguous completed prefix.

## Áp dụng vào hệ thống thật

Per-key sequencing trong worker shard, version guard ở target để reject stale writes.

## Những đường lỗi cần hiểu

Out-of-order DB upsert đè record mới bằng cũ; commit high watermark mất work khi crash.

## Lần theo bằng chứng khi có sự cố

Log partition/offset/entity version, kiểm tra checkpoint algorithm và replay tests.

## Đánh đổi và giới hạn sử dụng

Strict order giảm parallelism; chỉ giữ order đúng scope business.

## Thực hành, debugging và kết luận

Test delay một event đầu và cho event sau hoàn tất trước để lộ bug. Theo dõi sequence gap và stale-update rejection. Checkpoint chỉ qua đoạn liên tục đã được xử lý an toàn; offset lớn nhất đã xong không đủ khi có concurrency.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)

## Thực hành có điều kiện kiểm chứng

Cho offsets100,101,102 chạy parallel, ép101 chậm. Dù102 xong, next committed offset chỉ được tiến tới101 khi100 complete; sau101 complete mới có thể tới103 nếu102 đã xong. Nếu client API dùng record offset thay next-offset, tuân API mapping rõ. Test restart ở mỗi bước để chứng minh không skip101. Per-key state version guard bổ sung chống reordered effects.
