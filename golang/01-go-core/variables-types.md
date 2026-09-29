# Variables, types và zero values

## Bài toán và ví dụ đầu tiên

Một hệ thống có UserID và OrderID đều là string. Truyền nhầm hai giá trị vẫn có thể compile nếu API dùng string ở mọi nơi. Named type giúp compiler kiểm tra một phần ý nghĩa nghiệp vụ trước khi chương trình chạy.

## Đi từng bước qua một tình huống

Khai báo type UserID string làm UserID khác OrderID về type dù cùng underlying representation. Conversion có chủ đích ở boundary cho biết ta đang đổi cách diễn giải dữ liệu. Với số tiền, chọn integer minor units cùng currency và kiểm tra overflow; chỉ đổi float sang int không giải quyết làm tròn tiền tệ.

## Hiểu cơ chế từ kết quả quan sát

Zero value là trạng thái ban đầu khi biến chưa được gán: số bằng zero, bool false, string rỗng và một số kiểu bằng nil. Nó có thể là giá trị nghiệp vụ hợp lệ, nên đôi khi cần thêm bool hoặc pointer để phân biệt chưa cung cấp với đã cung cấp zero. := trong block con có thể shadow biến ngoài; error inner khác error outer dù cùng tên.

## Khái niệm và mô hình làm việc

Type định nghĩa phép toán hợp lệ; named types giúp chặn nhầm ID với amount dù underlying type giống nhau.

## Cơ chế và những ranh giới cần giữ

:= khai báo trong block và có thể shadow biến bên ngoài. Conversion khác assertion: conversion đổi biểu diễn hợp lệ, assertion kiểm tra dynamic type. Constants untyped được suy type khi dùng.

## Áp dụng vào hệ thống thật

Dùng type UserID string và số nguyên minor units cho amount với currency rõ ràng.

## Những đường lỗi cần hiểu

err bị shadow trong if rồi outer err nil; int overflow trong capacity estimate; zero time được hiểu nhầm là timestamp thật.

## Lần theo bằng chứng khi có sự cố

Bật go vet, xem scope và thêm boundary test overflow/zero; kiểm tra type ở JSON decode.

## Đánh đổi và giới hạn sử dụng

Named type tăng an toàn nhưng cần conversion ở boundary; alias phù hợp migration API.

## Thực hành, debugging và kết luận

Khi error đáng ra khác nil nhưng hàm vẫn return nil, kiểm tra scope và named return. Viết test cho zero, boundary numeric và input vắng mặt. Type assertion dùng với interface để kiểm tra dynamic type, khác conversion giữa các kiểu có phép chuyển hợp lệ; không dùng hai thuật ngữ thay thế nhau.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
