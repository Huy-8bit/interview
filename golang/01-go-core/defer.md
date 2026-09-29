# Defer: evaluation, LIFO và cleanup

## Bài toán và ví dụ đầu tiên

Một hàm mở file rồi có nhiều nhánh return lỗi. Nếu Close viết tay ở từng nhánh, dễ bỏ sót một nhánh khi thêm validation. Defer đăng ký cleanup gắn với lúc hàm kết thúc, làm acquire và release nằm gần nhau trong source.

## Đi từng bước qua một tình huống

Arguments của deferred call được đánh giá khi đăng ký. Với x=1, defer fmt.Println(x), rồi x=2, call in 1. Với defer func(){fmt.Println(x)}(), closure đọc x khi chạy nên in 2. Nhiều defer chạy theo thứ tự ngược đăng ký, tương tự tháo những tài nguyên lồng nhau từ trong ra ngoài.

## Hiểu cơ chế từ kết quả quan sát

Named return được gán trước khi defer chạy nên defer có thể sửa giá trị trả về; dùng thận trọng vì nó khiến return khó đọc. Defer chạy khi return hoặc unwind panic trong goroutine đó, không chạy sau os.Exit. Defer trong loop chưa kết thúc ở cuối iteration mà ở cuối function chứa nó.

## Khái niệm và mô hình làm việc

Defer đăng ký call chạy khi function return hoặc unwind panic; không chạy sau os.Exit.

## Cơ chế và những ranh giới cần giữ

Receiver và arguments được evaluate lúc đăng ký; closure có thể đọc biến tại thời điểm chạy. Defers chạy LIFO; named return đã được gán trước defer nên defer có thể đổi kết quả.

## Áp dụng vào hệ thống thật

Acquire rồi ngay lập tức defer release sau khi kiểm tra err. Với loop mở nhiều files, tách iteration thành function để close từng file sớm.

## Những đường lỗi cần hiểu

defer trong loop giữ hàng nghìn FD tới cuối function; defer đặt trước kiểm tra err có thể gọi Close trên nil.

## Lần theo bằng chứng khi có sự cố

Theo dõi open FD, xem lifetime function và lỗi cleanup; benchmark trước khi bỏ defer vì compiler tối ưu nhiều trường hợp.

## Đánh đổi và giới hạn sử dụng

Defer làm cleanup dễ review; explicit release hữu ích khi lifetime ngắn hơn function.

## Thực hành, debugging và kết luận

Với loop đọc nhiều file, dùng helper xử lý một file có defer Close để release mỗi vòng. Chỉ defer Close sau khi kiểm tra mở thành công. Khi operation và Close cùng lỗi, chọn policy giữ lỗi chính và bổ sung cleanup error thay vì ghi đè nguyên nhân. Lab core_test.go có ví dụ chạy được về argument và closure.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Code traps: dự đoán trước khi chạy

Chương trình độc lập:

```go
package main
import "fmt"
func result() (n int) {
    defer func() { n++ }()
    return 4
}
func main() {
    x := 1
    defer fmt.Println("argument", x)
    defer func() { fmt.Println("closure", x) }()
    x = 2
    fmt.Println(result())
}
```

### Giải thích code và kết quả

result gán named return n=4 trước khi defer tăng n thành5, nên main in5. Defer fmt.Println nhận x=1 ngay lúc đăng ký. Closure đọc x lúc main kết thúc, khi x đã2; vì LIFO, closure in trước argument. Output tiếp là closure2 rồi argument1. Không có goroutine; sự khác nhau đến từ evaluation time và thứ tự defer, không phải scheduler.

Output: `5`, rồi `closure 2`, rồi `argument 1`. Return expression gán named result trước defer; closure sửa result. Argument x cho Println evaluate lúc defer đăng ký; closure đọc x lúc exit. LIFO quyết định closure chạy trước deferred Println.

Resource loop: gọi helper cho mỗi file để `defer file.Close()` chạy cuối iteration helper. Đặt defer trong outer function chỉ Close tất cả ở outer return; với nhiều files sẽ giữ FD không cần thiết. Cleanup error phải return/join/log theo policy, không bỏ qua. Defer không chạy khi process bị kill hay os.Exit. Compiler có open-coded defer optimization ở nhiều cases; benchmark trên toolchain thật trước rewrite cleanup.

[Executable examples](../examples/core_test.go) kiểm tra argument capture và named return.
