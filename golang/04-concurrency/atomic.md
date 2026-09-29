# Atomics và immutable publication

## Bài toán và ví dụ đầu tiên

Một metric đếm request được cập nhật bởi nhiều goroutine. Ta cần mỗi lần tăng không bị mất, nhưng không cần khóa nhiều field cùng nhau. Atomic là thao tác mà các goroutine quan sát như một bước không bị chen giữa theo semantics được định nghĩa; nó phù hợp với state nhỏ như counter.

## Đi từng bước qua một tình huống

Dùng atomic.Int64 và Add(1) giữ increment thành một operation. Load rồi Store(Load()+1) là hai operation và có thể mất cập nhật. Compare-and-swap, viết tắt CAS, chỉ đổi giá trị nếu nó vẫn bằng giá trị đã quan sát; nếu goroutine khác đổi trước, caller phải tính lại từ state mới chứ không tiếp tục với giả định cũ.

## Hiểu cơ chế từ kết quả quan sát

Publish config bằng atomic.Pointer chỉ đồng bộ việc đưa pointer mới cho reader. Config cùng mọi map/slice bên trong phải được xây xong trước khi publish và không sửa sau đó. Nếu writer reuse backing array cũ rồi mutate, reader vẫn có data race dù pointer được lưu bằng atomic. Snapshot bất biến có nghĩa bất biến cả object graph cần chia sẻ.

## Khái niệm và mô hình làm việc

Atomic operations phù hợp counters và state transition nhỏ; chúng không tự tạo transaction trên nhiều fields.

## Cơ chế và những ranh giới cần giữ

Dùng typed atomic.Int64/Pointer; CAS cần loop khi update phụ thuộc current state. Sau publish pointer, snapshot phải immutable cả nested maps/slices.

## Áp dụng vào hệ thống thật

Publish routing snapshot mới và giữ readers không lock.

## Những đường lỗi cần hiểu

Atomic pointer nhưng mutate object phía sau; CAS retry loop spin khi contention; copy atomic value sau use.

## Lần theo bằng chứng khi có sự cố

Race test nested state, đo failed CAS và CPU; kiểm tra invariant chứ không chỉ data race.

## Đánh đổi và giới hạn sử dụng

Mutex đơn giản hơn nếu state nhiều field hoặc update phức tạp.

## Thực hành, debugging và kết luận

Với số dư và version phải thay đổi cùng nhau, mutex hoặc một snapshot chứa cả hai thường rõ hơn các atomic rời. CAS retry nhiều dưới contention có thể tốn CPU mà completion thấp; đo tỷ lệ retry và profile trước khi gọi nó nhanh hơn lock. Không copy atomic value sau khi dùng; race detector cần chạy cả đường truy cập nested state.



## Code: counter độc lập và giới hạn của phép cộng nguyên tử

```go
package main

import (
    "fmt"
    "sync"
    "sync/atomic"
)

func main() {
    var requests atomic.Int64
    var wg sync.WaitGroup
    for i := 0; i < 2; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            requests.Add(1)
        }()
    }
    wg.Wait()
    fmt.Println(requests.Load())
}
```

### Giải thích code từng bước

requests có zero value0. Mỗi worker gọi một Add nguyên tử, nên không có khoảng read-modify-write mà worker kia chen vào làm mất cập nhật. WaitGroup chờ cả hai xong; Load cuối trả2. Nếu cần đọc trong lúc workers hoạt động, vẫn dùng Load thay vì trộn atomic với truy cập memory không đồng bộ. Không copy requests sau khi bắt đầu dùng.

Đổi thành hai atomic fields balance và version không tạo một transaction: writer có thể cập nhật balance rồi bị tạm ngừng trước version, reader thấy cặp không đồng nhất. Snapshot immutable đặt cả hai trong một object được publish một lần, hoặc mutex quanh cặp, có thể diễn đạt invariant rõ hơn. Race detector không phát hiện cặp sai nghiệp vụ nếu mọi access riêng lẻ đều atomic hợp lệ.

Trong production, counter telemetry độc lập phù hợp ví dụ. Một giới hạn số slot cần check-and-update atomic đúng, thường qua CAS loop hoặc semaphore; Load kiểm tra nhỏ hơn limit rồi Add riêng vẫn có race condition vượt limit. CAS thất bại nghĩa state đã đổi, phải đọc/tính lại hoặc bỏ theo policy. Đo CPU dưới contention trước khi thay một mutex dễ đọc bằng loop lock-free khó chứng minh.

## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
