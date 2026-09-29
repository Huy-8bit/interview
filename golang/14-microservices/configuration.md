# Configuration lifecycle

## Bài toán và ví dụ đầu tiên

Một thay đổi timeout được deploy đồng loạt làm mọi request fail sớm. Configuration là input ảnh hưởng behavior production, nên cần validation, version và rollout như code chứ không chỉ đọc env string.

## Đi từng bước qua một tình huống

Parse config ở startup thành typed struct, kiểm tra duration >0, pool budgets và required fields. Immutable snapshot giúp nhiều goroutine đọc an toàn. Nếu hot reload, xây snapshot mới đầy đủ rồi publish atomic/lock; đừng sửa map từng field trong lúc readers dùng.

## Hiểu cơ chế từ kết quả quan sát

Default phải có ý nghĩa rõ và phân biệt missing với zero hợp lệ. Config secret cần kênh/retention riêng. Một field tăng pool mỗi replica phải được xét theo max replica count; validation cục bộ không chứng minh fleet budget hợp lý.

## Khái niệm và mô hình làm việc

Config là versioned operational input cần validation và ownership.

## Cơ chế và những ranh giới cần giữ

Parse typed schema, reject invalid budgets, immutable snapshot publish khi hot reload; distinguish startup-only settings như pool identity.

## Áp dụng vào hệ thống thật

Timeout, max replicas và total DB connection budget được validate cùng nhau.

## Những đường lỗi cần hiểu

Partial reload state không nhất quán; zero timeout vô tình unlimited; drift giữa pods.

## Lần theo bằng chứng khi có sự cố

Log config version/hash và safe values, diff rollout; không log secrets.

## Đánh đổi và giới hạn sử dụng

Hot reload giảm restart nhưng tăng concurrency/recovery complexity; restart rollout có thể đơn giản hơn.

## Thực hành, debugging và kết luận

Log config version và non-secret effective values để incident có thể đối chiếu. Canary thay đổi, đo SLO và có rollback. Test malformed env, unit conversion và reload failure giữ snapshot cũ thay vì publish trạng thái nửa hợp lệ.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Reload config gồm rate cap và pool cap cần validate quan hệ tổng trước publish. Build một immutable Config mới, không update từng field shared object vì request có thể thấy half old/half new. Nếu pool endpoint đổi, tạo dependency mới và health-check rồi swap owner có drain; atomic config pointer không tự quản connection pool lifecycle.
