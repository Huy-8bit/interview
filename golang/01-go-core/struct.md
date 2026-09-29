# Struct layout và composition

## Bài toán và ví dụ đầu tiên

Request đăng ký user có name và role. Nếu decode thẳng JSON vào domain User có field Admin, client có thể gửi field mà endpoint không định cho phép sửa. Struct gom dữ liệu theo một mục đích; request DTO và object domain có thể cần hai type riêng để giữ boundary rõ.

## Đi từng bước qua một tình huống

DTO nhận những field được phép nhập, validation kiểm tra giá trị, rồi service tạo domain object với quyền mặc định. JSON tag chỉ đổi tên hoặc cách encode field, không tự kiểm tra email, quyền hay invariant. Embedding một type có thể promote method ra outer type; điều đó mở rộng API và không tạo quan hệ subclass như nhiều ngôn ngữ OO.

## Hiểu cơ chế từ kết quả quan sát

Struct assignment copy field values, nên pointer/slice/map vẫn có thể chia sẻ storage. Alignment và padding là chỗ compiler chèn để field có địa chỉ phù hợp kiến trúc; unsafe.Sizeof chỉ đo phần struct trực tiếp, không cộng heap data được tham chiếu. Đổi thứ tự field có thể giảm footprint nhưng còn ảnh hưởng readability và serialization assumptions.

## Khái niệm và mô hình làm việc

Struct gom state có invariant chung; embedding promote method nhưng không tạo subclass.

## Cơ chế và những ranh giới cần giữ

Fields có alignment/padding; unsafe.Sizeof không tính allocations được pointer/slice tham chiếu. JSON tags là metadata của encoder, không phải validation.

## Áp dụng vào hệ thống thật

Tách request DTO khỏi domain object để input không ghi đè field privilege.

## Những đường lỗi cần hiểu

Copy struct chứa slice vẫn alias; exported field phá invariant; embedding vô tình mở rộng public API.

## Lần theo bằng chứng khi có sự cố

Kiểm tra field ownership, marshaled payload và benchmark layout nếu memory thực sự chi phối.

## Đánh đổi và giới hạn sử dụng

Ưu tiên readability trước packing; không export toàn bộ domain chỉ để ORM tiện dùng.

## Thực hành, debugging và kết luận

Khi cache hàng triệu record, đo kích thước thực và heap profile trước khi tối ưu layout. Test mutation của nested fields để làm rõ shallow copy. Giữ field nhạy cảm không export nếu caller không nên tự sửa; expose method có validation khi cần bảo vệ invariant.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
