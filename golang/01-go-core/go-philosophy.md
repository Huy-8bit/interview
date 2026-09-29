# Go philosophy

## Bài toán và ví dụ đầu tiên

Một service nhỏ thường dễ hiểu lúc mới viết nhưng nhanh chóng khó sửa khi có interface cho mọi struct, constructor mở network và goroutine ở mọi bước. Go khuyến khích code mà người đọc có thể theo luồng dữ liệu và đường lỗi trực tiếp. Đơn giản ở đây là ít điều phải đoán, không phải ít dòng nhất.

## Đi từng bước qua một tình huống

Hãy bắt đầu một endpoint bằng handler gọi service đồng bộ rồi service gọi repository. Inject database và clock tại constructor để test thay nguồn thời gian hoặc dữ liệu. Chỉ tạo interface cho hành vi consumer thực sự cần thay thế, ví dụ GetUser, thay vì xuất toàn bộ API của driver vào domain.

## Hiểu cơ chế từ kết quả quan sát

Composition ghép các thành phần nhỏ thành hành vi lớn; nó không cần cây inheritance. Zero value hữu ích cho mutex, buffer hoặc kiểu dữ liệu được thiết kế phù hợp, nhưng dependency bắt buộc như DB vẫn nên được xác thực ở constructor. Error trả về làm failure path hiện ra ở call site.

## Khái niệm và mô hình làm việc

Go ưu tiên composition, explicit control flow và API nhỏ. Zero value dùng được giúp giảm trạng thái khởi tạo không hợp lệ.

## Cơ chế và những ranh giới cần giữ

Bắt đầu bằng concrete function; extract interface tại consumer khi có substitution thật. Gofmt thống nhất hình thức; error values làm đường lỗi hiển thị ở call site.

## Áp dụng vào hệ thống thật

Service user có constructor nhận repository và clock; business code không import HTTP framework.

## Những đường lỗi cần hiểu

Interface cho từng struct và goroutine cho từng bước biến code tuần tự thành lifecycle khó quản lý.

## Lần theo bằng chứng khi có sự cố

Đọc import graph và trace một request; đếm object cần Close/Stop và ai sở hữu chúng.

## Đánh đổi và giới hạn sử dụng

Sự rõ ràng thường đáng giá hơn framework tự động; tránh abstraction khi chỉ có một caller.

## Thực hành, debugging và kết luận

Khi review, theo một request từ đầu tới cuối và xác định nơi tài nguyên được acquire/release. Nếu phải nhảy qua nhiều abstraction để biết ai Close hoặc ai bắt lỗi, cân nhắc thu gọn boundary. Tính dễ đọc giúp incident response và thay đổi nghiệp vụ; benchmark chỉ dẫn tối ưu những đoạn thực sự chi phối chi phí.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
