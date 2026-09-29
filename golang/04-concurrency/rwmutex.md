# RWMutex và writer latency

## Bài toán và ví dụ đầu tiên

Một routing table có hàng nghìn lượt đọc mỗi giây và thỉnh thoảng cập nhật. Mutex cho mọi reader làm các lượt đọc lần lượt đi qua critical section. RWMutex cho nhiều reader cùng vào khi không có writer, nhưng writer vẫn cần độc quyền để bảng không bị thấy ở trạng thái đang sửa.

## Đi từng bước qua một tình huống

Goroutine A và B gọi RLock rồi đọc table. Writer C gọi Lock và phải chờ A, B RUnlock. Khi có writer đang chờ, reader mới không được mãi chen vào trước nó theo contract của RWMutex. Nếu A giữ RLock rồi tự gọi Lock để “nâng cấp”, A chờ độc quyền trong khi chính A vẫn là reader chưa thoát; đây là deadlock.

## Hiểu cơ chế từ kết quả quan sát

RLock không cho phép ghi chỉ vì thay đổi có vẻ nhỏ. Lazy initialization, tăng hit count hoặc sửa một slice lấy từ map đều là write. Một pointer được đọc dưới RLock rồi sử dụng sau RUnlock cần dữ liệu phía sau bất biến hoặc cơ chế lifetime riêng. Việc trả pointer ra ngoài lock không kéo dài sự bảo vệ của lock.

## Khái niệm và mô hình làm việc

RWMutex cho nhiều readers hoặc một writer; mọi write vẫn cần exclusive Lock.

## Cơ chế và những ranh giới cần giữ

Writer chờ sẽ chặn new readers để có cơ hội tiến triển. Không upgrade RLock sang Lock hoặc recursive read lock khi writer chờ.

## Áp dụng vào hệ thống thật

Read-heavy registry với read work đủ lớn có thể hưởng lợi; benchmark với Mutex.

## Những đường lỗi cần hiểu

Read lock giữ trong I/O khiến writer chờ lâu; RLock rồi Lock cùng G deadlock.

## Lần theo bằng chứng khi có sự cố

Đo read/write ratio, hold duration, mutex profile và writer P99.

## Đánh đổi và giới hạn sử dụng

Tiny reads có thể không bù bookkeeping; không dùng vì chỉ thấy workload có nhiều reads.

## Thực hành, debugging và kết luận

Benchmark với tỷ lệ đọc/ghi và độ dài critical section thực. Với read chỉ vài nanosecond, bookkeeping của RWMutex có thể không đáng. Ở production theo dõi writer latency: reader giữ lock trong network I/O làm một bản cập nhật config chờ rất lâu. Copy snapshot dưới lock rồi làm việc bên ngoài, hoặc publish snapshot bất biến khi khối lượng đọc và kích thước dữ liệu phù hợp.



## Code: đọc snapshot để không mang mutable state ra ngoài lock

```go
package registry

import "sync"

type Registry struct {
    mu sync.RWMutex
    routes map[string]string
}

func (r *Registry) Set(name, target string) {
    r.mu.Lock()
    defer r.mu.Unlock()
    if r.routes == nil { r.routes = make(map[string]string) }
    r.routes[name] = target
}

func (r *Registry) Snapshot() map[string]string {
    r.mu.RLock()
    defer r.mu.RUnlock()
    out := make(map[string]string, len(r.routes))
    for k, v := range r.routes { out[k] = v }
    return out
}
```

### Giải thích code từng bước

Set lấy write lock cho cả initialization và assignment. Snapshot giữ read lock khi iterate để writer không sửa map trong lúc copy. Kết quả là map mới, nên caller sửa map trả về không thay r.routes; string values là giá trị bất biến theo API thông thường. Nếu values là *Route có map/slice mutable bên trong, copy này chưa độc lập sâu, phải thiết kế lại ownership hoặc clone phần cần thiết.

Snapshot vẫn giữ RLock suốt vòng copy; với hàng triệu routes, writer có thể đợi lâu. Một phương án khác là writer xây immutable map mới rồi publish pointer, nhưng khi đó mọi reader phải tuân không mutate và memory tạm thời có thể giữ hai snapshot. Đây là trade-off read/write latency và allocation cần đo theo kích thước registry.

Thực hành bằng hai readers cùng gọi Snapshot và writer liên tục Set trên keys riêng; chạy -race để kiểm tra map state, rồi benchmark Mutex so với RWMutex ở tỷ lệ ghi và kích thước map khác nhau. Test correctness không cần sleep: hoàn tất workers qua WaitGroup và assert snapshot có keys hợp lệ. Performance test riêng mới đo throughput/latency, không dùng timing assertion mong manh trong unit test.

## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
