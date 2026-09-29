# Value versus pointer

## Bài toán và ví dụ đầu tiên

Hàm đổi tên user nhận struct nhưng caller không thấy thay đổi. Go luôn truyền value; nhận struct nghĩa là nhận bản copy các field. Pointer cũng được truyền bằng value, nhưng bản copy pointer vẫn trỏ tới cùng object nên có thể dùng để sửa object đó.

## Đi từng bước qua một tình huống

So sánh change(u User) gán u.Name với change(u *User) gán u.Name. Trường hợp đầu sửa bản copy, trường hợp sau sửa object qua địa chỉ được copy. Nếu User có field Tags []string, bản copy User vẫn có slice header trỏ chung array; sửa Tags[0] có thể hiện ra ở caller dù đổi Name không hiện ra.

## Hiểu cơ chế từ kết quả quan sát

Pointer phù hợp mutation có chủ đích, identity hoặc tránh copy object lớn. Nó cũng thêm khả năng nil và sharing, làm ownership cần rõ. Dấu & không ra lệnh allocate heap; compiler chọn placement theo lifetime và escape. Value cũng có thể nằm trên heap khi được chứa trong object dài hạn.

## Khái niệm và mô hình làm việc

Go luôn pass by value; pointer value được copy và hai bản copy có thể trỏ cùng object.

## Cơ chế và những ranh giới cần giữ

Chọn pointer khi cần mutation, identity hoặc tránh copy object lớn; slice/map cũng là value có tham chiếu tới storage chung. Pointer không đảm bảo heap và value không đảm bảo stack.

## Áp dụng vào hệ thống thật

DTO nhỏ immutable truyền value; service có mutex truyền pointer và không copy sau first use.

## Những đường lỗi cần hiểu

Copy struct chứa mutex gây hai lock bảo vệ cùng map; nil receiver dereference panic.

## Lần theo bằng chứng khi có sự cố

Dùng go vet copylocks, race detector và escape output tại call site thay vì đoán từ dấu &.

## Đánh đổi và giới hạn sử dụng

Value giảm aliasing nhưng copy field reference vẫn shallow; pointer cần ownership rõ.

## Thực hành, debugging và kết luận

Với struct chứa mutex hoặc atomic đã dùng, không copy sang instance khác. Chạy go vet để phát hiện một số copylock và race detector trên đường shared state. Chọn pointer/value vì semantics trước; benchmark cả call site nếu copy cost thực sự lớn, tránh làm API khó dùng chỉ vì suy đoán pointer luôn nhanh hơn.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
