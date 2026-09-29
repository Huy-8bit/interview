# Context values: metadata của request, không phải túi dependency

## Bài toán và ví dụ dễ gặp

Middleware tạo trace ID để liên kết log của handler, service và HTTP call. Nếu thêm traceID string vào mọi chữ ký hàm, một thông tin quan sát có thể làm API nghiệp vụ khó đọc. Context values cho phép mang metadata gắn với request qua các tầng đã nhận context.

Ngược lại, service cần database để hoạt động thì DB không phải metadata của request. Giấu DB trong context khiến code compile được dù quên đặt value và chỉ lỗi lúc chạy. Dependency nên được cung cấp qua constructor hoặc struct; dữ liệu nghiệp vụ bắt buộc nên có kiểu và tham số rõ ràng.

```go
package metadata

import "context"

type traceKey struct{}

func WithTraceID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, traceKey{}, id)
}

func TraceID(ctx context.Context) (string, bool) {
    id, ok := ctx.Value(traceKey{}).(string)
    return id, ok
}
```

### Giải thích code từng bước

traceKey là kiểu không export riêng của package, giúp tránh đụng key với thư viện khác dùng một string chung như "id". WithValue tạo derived context trỏ về parent; nó không sửa parent và không tự thêm deadline. TraceID dùng assertion có biến ok, nên thiếu metadata không gây panic. Caller quyết định dùng log không có ID hoặc tạo ID ở đúng boundary.

Nếu lưu pointer tới map rồi nhiều goroutine cùng sửa map, Context không biến map đó thành thread-safe. An toàn concurrent của các method context chỉ áp dụng vào việc dùng context, không cấp lock cho object nằm trong value. Nên ưu tiên metadata bất biến và nhỏ.

## Cơ chế lookup và lifetime

Khi tìm key, một context chứa value có thể kiểm tra key của nó rồi tìm tiếp ở parent. Về mặt mental model đây là chuỗi lớp bổ sung metadata, không phải map toàn cục. Cùng key ở child che giá trị của parent trong nhánh đó; nhánh khác vẫn nhìn thấy giá trị parent. Không dùng values như kho ghi cập nhật liên tục giữa goroutine.

Context được giữ bao lâu thì value có thể bị giữ theo bấy lâu. Lưu buffer 20 MB để tiện đọc trong vài hàm có thể khiến buffer sống lâu hơn dự định khi một worker giữ context. Context không có phương thức liệt kê mọi value để caller quản lý như một dictionary; package nên cung cấp accessor có ý nghĩa rõ.

## Production và các ranh giới tin cậy

Trace ID dùng để liên kết sự kiện, không phải bằng chứng user được phép truy cập dữ liệu. Authentication middleware có thể đặt identity đã kiểm chứng vào context; service vẫn phải thực hiện authorization — kiểm tra quyền trên tài nguyên cụ thể — từ identity đó. Không tin tenant ID do client tự gửi chỉ vì nó đã được đặt vào ctx.

Giả sử hai thư viện đều dùng key string "user" nhưng một bên lưu string, một bên lưu struct. Một bản nâng cấp có thể làm type assertion thất bại ở service không liên quan. Key kiểu riêng và accessor tập trung làm lỗi này dễ tránh và dễ phát hiện trong test.

## Debugging, trade-off và tổng kết

Khi value biến mất, kiểm tra có đoạn thay ctx bằng Background, tạo key khác kiểu hoặc đọc ngoài nhánh đã thêm value không. Khi memory tăng, nhìn retention path tới context và value lớn, không chỉ số lần WithValue được gọi. Dữ liệu tồn tại nhiều request nên có owner riêng ngoài context.

Values làm metadata đi qua API dễ hơn nhưng làm dependency khó thấy nếu lạm dụng. Giữ chúng cho thông tin request có phạm vi xuyên tầng, định nghĩa accessor tại package sở hữu thông tin và giữ object được truyền bất biến khi có nhiều goroutine cùng đọc.

## Đọc tiếp

- [Context: cây lifetime và cooperative cancellation](context-basics.md)
- [Goroutine leaks: blocked work còn giữ tài nguyên](../04-concurrency/goroutine-leak.md)
- [graceful-shutdown](../06-http-backend/graceful-shutdown.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/context)
