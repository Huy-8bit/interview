# Packages và modules

## Bài toán và ví dụ đầu tiên

Một chương trình compile ở máy tác giả nhưng CI không tìm thấy dependency vì go.mod có replace tới thư mục local. Package là đơn vị source được import và có namespace; module là tập package được phát hành theo version và định danh bởi module path.

## Đi từng bước qua một tình huống

Import example.com/project/store trỏ tới package theo module path và thư mục, không phải tên folder tùy ý trong máy người viết. go.mod ghi yêu cầu version và cấu hình module; go.sum lưu checksum phục vụ kiểm chứng nội dung dependency, không phải lockfile lựa chọn một graph độc lập với go.mod.

## Hiểu cơ chế từ kết quả quan sát

Minimal Version Selection chọn các version cần để thỏa yêu cầu trong graph theo quy tắc Go. Khi có thay đổi dependency, xem go list -m all và go mod graph để hiểu vì sao một version được chọn. Major version v 2 trở lên thường đi cùng suffix trong module/import path theo quy tắc module versioning.

## Khái niệm và mô hình làm việc

Package là đơn vị encapsulation/import; module là tập package được version bằng go.mod.

## Cơ chế và những ranh giới cần giữ

go.mod ghi module path và Go version; go.sum chứa checksum, không phải lockfile chọn version. Minimal Version Selection chọn version cao nhất được yêu cầu trong graph. Major v 2+ thường có suffix /v 2.

## Áp dụng vào hệ thống thật

Pin toolchain trong CI; dùng go mod tidy, go mod verify và xem go list -m all khi dependency thay đổi.

## Những đường lỗi cần hiểu

replace trỏ local path làm CI fail; import cycle báo boundary sai; init mở network khiến test bất ổn.

## Lần theo bằng chứng khi có sự cố

So sánh go env, go.mod, go.sum và module graph giữa local/CI; kiểm tra GOPRIVATE cho private modules.

## Đánh đổi và giới hạn sử dụng

Một module đơn giản dễ release; nhiều module cần khi lifecycle version thực sự độc lập.

## Thực hành, debugging và kết luận

Dùng clean checkout/CI để kiểm tra không phụ thuộc local replace hay file ngoài repo. Đừng mở network trong init nếu có thể khởi tạo dependency ở main: init side effect làm import/test khó kiểm soát. Ghi toolchain, GOOS/GOARCH và build flags để incident có thể tái hiện đúng binary.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
