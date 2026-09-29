# Go project structure không có một luật duy nhất

## Bài toán và ví dụ đầu tiên

Một feature đổi logic discount nhưng phải sửa handler, SQL helper và package utils chung của nhiều module. Vấn đề cấu trúc project là dependency và ownership khó thấy, không đơn giản là thiếu folder có tên chuẩn.

## Đi từng bước qua một tình huống

Bắt đầu một module orders chứa use cases và interface nhỏ cho những dependency nó dùng. Entrypoint trong cmd lắp DB, clients và server; internal giới hạn import theo quy tắc Go. Không tạo package common chứa mọi thứ chỉ vì hai file cần dùng chung một helper.

## Hiểu cơ chế từ kết quả quan sát

Package là đơn vị dependency thực mà compiler kiểm tra; folder chỉ có ý nghĩa khi phản ánh boundary đó. Import cycle báo các phần đang phụ thuộc vòng và có thể cần chuyển interface về consumer hoặc đặt orchestration ở tầng cao hơn. Domain không cần biết HTTP status nếu status thuộc transport adapter.

## Khái niệm và mô hình làm việc

Go không có một project structure chính thức bắt buộc cho mọi project; package/import rules mới là ràng buộc tooling.

## Cơ chế và những ranh giới cần giữ

Ví dụ cmd/api, internal/user, internal/payment, internal/platform, migrations, configs. pkg/ chỉ khi có public reusable packages thật, có thể bỏ. internal có import visibility rule của Go toolchain.

## Áp dụng vào hệ thống thật

cmd chỉ wiring/lifecycle; domain nằm internal; migrations versioned; config schema validate startup.

## Những đường lỗi cần hiểu

pkg thành dumping ground; utils chứa unrelated behavior; folder architecture kéo import cycles.

## Lần theo bằng chứng khi có sự cố

go list/import graph và tìm owner của change; package name phải nói trách nhiệm.

## Đánh đổi và giới hạn sử dụng

Small app bắt đầu ít packages rồi tách theo cohesion; không scaffold rỗng hàng chục layers.

## Thực hành, debugging và kết luận

Trace một feature từ request tới storage và xem thay đổi có nằm trong một vùng dễ hiểu không. Refactor từng boundary có test behavior, tránh di chuyển mọi file cùng lúc. Một project nhỏ có thể dùng ít package; số folder không là thước đo architecture.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Ví dụ triển khai

```text
cmd/api/main.go
cmd/worker/main.go
internal/user/
internal/payment/
internal/platform/
pkg/                 # optional reusable public APIs
migrations/
configs/              # schema/examples, khong luu secrets that
```

Một module có thể tạo hai binaries API/worker nhưng vẫn dùng chung domain packages. Chỉ tách module khi version/release lifecycle cần độc lập.
