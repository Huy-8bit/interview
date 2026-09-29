# Integration testing boundaries thật

## Bài toán và ví dụ đầu tiên

Repository unit test với mock pass nhưng SQL thật sai kiểu nullable hoặc transaction giữ lock khác giả định. Integration test chạy qua boundary thật để kiểm chứng contract mà fake không mô phỏng đầy đủ.

## Đi từng bước qua một tình huống

Dùng database/service thử nghiệm cô lập, apply schema/migrations rồi test query và cleanup. Điều phối concurrent transactions bằng barriers để ép collision. Không dùng production data hay endpoint thật để kiểm tra destructive behavior; test cần resource riêng và cleanup rõ.

## Hiểu cơ chế từ kết quả quan sát

Integration test chậm và nhiều biến môi trường hơn nên chọn behavior quan trọng: driver cancellation, constraints, pooling, protocol compatibility. Pin service versions và ghi cấu hình để failure tái hiện. Health-ready của dependency cần dựa trạng thái thực, không Sleep một số giây đoán.

## Khái niệm và mô hình làm việc

Integration test xác nhận driver/protocol/schema behavior không thể suy từ fake.

## Cơ chế và những ranh giới cần giữ

Use isolated DB/schema, migrations đúng version, deterministic fixtures và cleanup; external dependency setup có timeout.

## Áp dụng vào hệ thống thật

Test unique-key concurrent insert, transaction rollback, query cancellation và pool slot release.

## Những đường lỗi cần hiểu

Shared database làm tests flaky; sleeping chờ broker; cleanup bỏ namespace.

## Lần theo bằng chứng khi có sự cố

Capture server logs/query states khi fail; test version matrix có chủ đích.

## Đánh đổi và giới hạn sử dụng

Không gọi compile test là integration test; ghi rõ dependency nào thực sự chạy.

## Thực hành, debugging và kết luận

Tách báo cáo compile/unit pass với integration đã chạy. Lab SQL trong repo chỉ compile được chưa là bằng chứng với PostgreSQL thật. CI cần setup repeatable và artifacts lỗi đã redacted; test phải xác minh durable state sau failure, không chỉ process exit0.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

Transaction test có hai concurrent sessions reserve cùng last inventory item; expected total successful reservations1 và stock không âm. Sau cancel long query, query nhẹ từ cùng limited pool phải acquire được để chứng minh release. Những kiểm tra này cần PostgreSQL/driver thật; stdlib example compile pass không đủ bằng chứng. Record database/driver versions và migrated schema.
