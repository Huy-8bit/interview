# Methods và method sets

## Bài toán và ví dụ đầu tiên

Một Counter có method Inc nhưng gọi xong value vẫn zero. Nếu receiver là Counter theo value, method đang sửa bản copy. Method receiver quyết định hàm nhận state như thế nào và ảnh hưởng cả việc type thỏa interface.

## Đi từng bước qua một tình huống

Với func (c *Counter) Inc(), biến local addressable có thể gọi c.Inc() nhờ compiler lấy địa chỉ. Nhưng nếu interface yêu cầu Inc thì Counter value chưa chắc thỏa; *Counter mới có method đó trong method set. Đưa value vào interface không cho compiler tùy tiện biến nó thành pointer tới object caller như khi gọi trực tiếp.

## Hiểu cơ chế từ kết quả quan sát

Value receiver phù hợp value nhỏ bất biến hoặc semantics copy. Pointer receiver cần khi mutate, tránh copy lock hoặc giữ identity. Method trên nil pointer chỉ an toàn khi body tự xử lý nil; lời gọi method không tự đảm bảo receiver có object. Nên nhất quán receiver style khi type có state mutable để giảm bất ngờ.

## Khái niệm và mô hình làm việc

Method gắn behavior vào named type; receiver value copy state, pointer receiver cho phép mutation trên object.

## Cơ chế và những ranh giới cần giữ

T method set không gồm method chỉ khai báo trên *T. Addressable local T gọi pointer method được bằng compiler convenience; interface assignment vẫn tuân method set.

## Áp dụng vào hệ thống thật

Giữ receiver style nhất quán khi type có mutable state; API có mutex dùng *T.

## Những đường lỗi cần hiểu

Value receiver tăng counter trên bản copy; interface compile failure bị hiểu nhầm là compiler không tự lấy địa chỉ.

## Lần theo bằng chứng khi có sự cố

Viết compile-time interface assertion và unit test observable mutation.

## Đánh đổi và giới hạn sử dụng

Value receiver tốt cho value object nhỏ; pointer receiver mang nil và aliasing vào contract.

## Thực hành, debugging và kết luận

Viết compile-time assertion cho interface boundary và test quan sát state sau method. Nếu method copy struct có mutex nhưng map bên trong vẫn chung, hai lock khác nhau có thể bảo vệ cùng dữ liệu sai cách. Dùng pointer receiver và không sao chép type sau khi bắt đầu dùng.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
