# Những lỗi context thường gặp và vì sao chúng xảy ra

## Bài toán: có ctx ở mọi hàm nhưng không giảm được tài nguyên

Một dịch vụ đã bổ sung context vào API nhưng số goroutine vẫn tăng sau các đợt timeout. Khi review, ta cần lần theo hành vi thay vì chỉ tìm chữ `context.Context` trong signature. Ba điểm phải nối nhau là nguồn phát tín hiệu, thao tác quan sát và owner chờ thao tác kết thúc.

## Ví dụ một lỗi nhỏ làm mất cancellation

Repository nhận ctx rồi dùng Background khi gọi DB vì người viết nghĩ mỗi query cần context riêng. Background không có parent request, nên client rời đi không hủy query đó. Cách sửa là dùng ctx hoặc tạo child từ ctx. Context riêng về timeout không có nghĩa là context gốc độc lập.

Một lỗi khác là `defer cancel()` trong vòng lặp xử lý hàng chục nghìn item. Defer chỉ chạy khi hàm chứa vòng lặp return, không chạy sau mỗi iteration. Nếu mỗi vòng tạo timer context, tài nguyên của các child có thể được giữ lâu không cần thiết. Tách một iteration thành hàm riêng hoặc gọi cancel ngay sau operation, bảo đảm mọi đường return đều cleanup.

```go
func Process(ctx context.Context, jobs []int, work func(context.Context, int) error) error {
    for _, job := range jobs {
        child, cancel := context.WithTimeout(ctx, time.Second)
        err := work(child, job)
        cancel()
        if err != nil {
            return err
        }
    }
    return nil
}
```

### Giải thích code từng bước

Mỗi child có thời hạn tối đa một giây và vẫn bị parent giới hạn. Work chạy đồng bộ nên cancel ngay sau khi work trả về là đúng phạm vi. Biến err được giữ trước cleanup để hàm vẫn trả lỗi gốc. Không dùng defer tích lũy trong loop. Work có thể phớt lờ ctx, vì vậy code này vẫn cần contract rằng work biết dừng; chữ ký callback không tự bảo đảm hành vi đó.

## Busy loop, blocked send và tưởng rằng cancel là join

`for { select { case <-ctx.Done(): return; default: } }` không có công việc hữu ích trong default. Nó liên tục chạy khi chưa hủy và có thể chiếm cả core. Bỏ default nếu chỉ muốn chờ; nếu cần làm CPU work, chia thành chunk rồi kiểm tra ctx giữa các chunk.

Worker có thể quan sát cancellation ở đầu vòng nhưng sau đó kẹt khi gửi result. Khi caller bỏ cuộc, không còn ai receive. Thêm buffer chỉ trì hoãn lúc kẹt nếu số kết quả không bị giới hạn; thiết kế đường send có select hoặc quy định consumer luôn drain. Cancel xong vẫn cần done channel hoặc WaitGroup nếu owner phải biết cleanup hoàn tất.

## Sai lifetime của tác vụ nền

Dùng r.Context cho một job cần sống sau response khiến job nhận cancellation ngay khi handler kết thúc. Dùng Background để chữa lại khiến job không còn giới hạn hay người chịu trách nhiệm khi shutdown. Cách giải quyết bắt đầu từ yêu cầu sản phẩm: job có được phép mất không, ai retry, trạng thái lưu ở đâu. Job bền vững nên có record và worker owner; tác vụ ngắn trong request thì ở lại request lifetime.

## Production và cách kiểm chứng

Khi cảnh báo goroutine tăng, lấy profile trước và sau một request bị cancel có điều phối. Nếu stack cùng dừng ở send result, tập trung vào giao thức producer–consumer. Nếu stack ở driver, kiểm tra driver cancellation và server query. Nếu CPU tăng với stack trong loop, kiểm tra default và điều kiện thoát. Mỗi giả thuyết cần một quan sát có thể bác bỏ nó.

Test không nên chỉ assert err khác nil. Hãy kiểm tra worker đã hoàn tất bằng tín hiệu xác nhận, dependency fake đã nhận ctx bị hủy và tài nguyên sở hữu đã được trả. Với lệnh ghi từ xa, kiểm tra kết quả ở hệ thống đích hoặc mô phỏng response bị mất sau commit. Timeout của caller không tự nói được side effect đã xảy ra hay chưa.

## Tổng kết và trade-off

Context giải quyết truyền thông tin lifetime. Nó không thay thế đồng bộ, queue ownership, transaction semantics hay quản lý background job. Một bản sửa tốt làm rõ các trách nhiệm này trong code và test, không chỉ thêm một ctx vào danh sách tham số.

## Đọc tiếp

- [Context: cây lifetime và cooperative cancellation](context-basics.md)
- [Goroutine leaks: blocked work còn giữ tài nguyên](../04-concurrency/goroutine-leak.md)
- [graceful-shutdown](../06-http-backend/graceful-shutdown.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/context)
