# Mocks, fakes và contract tests

## Bài toán và ví dụ đầu tiên

Service tính shipping gọi provider ngoài. Mock/fake giúp test timeout hoặc rejection có điều phối mà không gửi request thật. Nhưng mock trả success ngay không phản ánh latency, cancellation hay partial failure của provider.

## Đi từng bước qua một tình huống

Consumer định nghĩa interface nhỏ; fake nhận context và có channel để test quyết định lúc hoàn tất. Kiểm tra operation identity được giữ qua retry và cancellation được nhận. Nếu dùng call expectations, chỉ assert tương tác là contract, tránh khóa cứng refactor nội bộ vô nghĩa.

## Hiểu cơ chế từ kết quả quan sát

Fake là một implementation đơn giản có behavior; mock thường nhấn vào expectation tương tác. Cả hai có thể sai contract nếu không có integration/contract tests đối chiếu adapter thật. Ví dụ fake DB không thể chứng minh QueryContext trả slot sau Rows.Close.

## Khái niệm và mô hình làm việc

Mock kiểm interactions khi interaction là contract; fake cung cấp behavior đơn giản, integration test kiểm adapter thật.

## Cơ chế và những ranh giới cần giữ

Small consumer interfaces tránh mocks khổng lồ. Fake phải mô phỏng error/cancel/ordering mà test phụ thuộc.

## Áp dụng vào hệ thống thật

Fake clock cho retry; httptest cho HTTP protocol; DB thật cho isolation.

## Những đường lỗi cần hiểu

Mock transaction luôn success che rollback bug; expected call order cứng dù contract cho parallelism.

## Lần theo bằng chứng khi có sự cố

Run same contract cases trên adapters khi khả thi; compare real driver cancellation.

## Đánh đổi và giới hạn sử dụng

Không dùng mock để chứng minh SQL plan, locks hay connection pooling.

## Thực hành, debugging và kết luận

Dùng deterministic fake cho concurrency thay vì Sleep. Test fake failure modes cùng service invariants. Khi mock setup dài hơn use case, xem interface có quá rộng hoặc responsibilities bị gộp; thu nhỏ boundary thay vì thêm nhiều matcher phức tạp.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)
