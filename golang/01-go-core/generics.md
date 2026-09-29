# Generics và constraints

## Bài toán và ví dụ đầu tiên

Ta muốn một hàm tìm phần tử trong []int và []string mà không viết hai bản hoặc chuyển mọi thứ thành any. Generics cho phép thuật toán nhận type parameter, giữ kiểm tra kiểu ở compile time trong phạm vi các operation được constraint cho phép.

## Đi từng bước qua một tình huống

Một Set[T comparable] có thể dùng map[T]struct{} vì comparable cho biết T hỗ trợ equality dùng cho key. Nếu thuật toán cần cộng, comparable chưa đủ; constraint phải bao gồm kiểu hỗ trợ phép cộng. ~int trong type set cho phép named type có underlying type int, không chỉ đúng type int.

## Hiểu cơ chế từ kết quả quan sát

Type parameter giúp tái dùng một thuật toán trên nhiều kiểu; interface hành vi giúp caller không phụ thuộc implementation cụ thể. Hai công cụ có thể kết hợp nhưng không thay thế nhau tự động. Compiler có chiến lược code generation riêng theo release; không giả định mỗi type luôn sinh một bản code hoàn toàn độc lập hay luôn không overhead.

## Khái niệm và mô hình làm việc

Generics tái dùng thuật toán với type safety; interface behavior và type parameter giải quyết nhu cầu khác nhau.

## Cơ chế và những ranh giới cần giữ

Constraint type set giới hạn operations; ~T chấp nhận underlying type T. comparable cần cho map keys. Compiler strategy phụ thuộc release, không giả định mọi instantiation đều được monomorphize độc lập.

## Áp dụng vào hệ thống thật

Dùng generic set hoặc slice transform khi giảm lặp và giữ API rõ; business service thường chỉ cần concrete types.

## Những đường lỗi cần hiểu

Constraint quá rộng gây compile errors; API generic nhiều parameters khó infer; dùng any rồi assertions mất lợi ích.

## Lần theo bằng chứng khi có sự cố

Đọc compiler error tại constraint, benchmark binary size/allocation nếu nằm hot path.

## Đánh đổi và giới hạn sử dụng

Không thay mọi interface bằng generic; runtime polymorphism cần interface value.

## Thực hành, debugging và kết luận

Bắt đầu từ một nhu cầu lặp lại cụ thể như queue/set. Test zero value, kiểu named và edge cases của algorithm; benchmark nếu API generic thay hot path cũ. Business service có nhiều type parameter khó infer có thể kém rõ hơn một struct cụ thể và một interface nhỏ.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
