# Service secrets và rotation

## Bài toán và ví dụ đầu tiên

Database password không nên nằm trong git hoặc xuất hiện ở startup logs. Secret có lifecycle cấp, dùng, rotate và thu hồi; application cần truy cập qua cơ chế môi trường/deployment phù hợp và quyền tối thiểu.

## Đi từng bước qua một tình huống

Load credential từ secret provider/mount theo nền tảng, không in DSN đầy đủ. Rotation có thể cần tạo connections mới rồi drain connections dùng credential cũ; chỉ đổi file chưa chắc pool tự đọc lại. Giữ cửa sổ chuyển tiếp theo policy hệ thống đích.

## Hiểu cơ chế từ kết quả quan sát

Env, file và secret manager có trade-offs về delivery, permissions và refresh; không có kênh tự an toàn nếu app log toàn config. Test và traces phải dùng dữ liệu giả hoặc redaction. Secret không nên truyền vào context values nếu không cần xuyên request.

## Khái niệm và mô hình làm việc

Secrets cần least privilege, short exposure và rotation; config values không phải mọi thứ đều secret.

## Cơ chế và những ranh giới cần giữ

Load qua secret manager/workload identity, tránh image/git/log; support overlap old/new credentials trong rotation có audit.

## Áp dụng vào hệ thống thật

DB credentials rotate với new pool rồi drain old pool trong budget.

## Những đường lỗi cần hiểu

Secret env dump vào crash logs; revoke old key trước clients refresh; JWKS cache vô hạn.

## Lần theo bằng chứng khi có sự cố

Audit access/rotation timestamps, auth failures theo key ID không key value.

## Đánh đổi và giới hạn sử dụng

Short TTL giảm exposure nhưng tăng dependency vào issuer availability; cache có bounded fallback.

## Thực hành, debugging và kết luận

Kiểm tra incident logs, error wrapping và crash dumps có lộ credential không. Test rotation trước khi hết hạn và failure khi provider không sẵn sàng. Phân biệt service identity với user authorization để không dùng một credential quyền rộng cho mọi operation.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)
