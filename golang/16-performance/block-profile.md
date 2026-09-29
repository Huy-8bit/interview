# Block profile

## Bài toán và ví dụ đầu tiên

P99 tăng trong khi CPU còn rảnh, nhiều công việc có thể đang chờ channel hoặc synchronization. Block profile lấy mẫu thời gian blocking ở các điểm được runtime hỗ trợ khi được bật.

## Đi từng bước qua một tình huống

Một hot entry tại send result có thể nghĩa downstream consumer chậm hoặc đã dừng. Một entry ở WaitGroup.Wait chỉ là nơi owner chờ; cần xem worker đang giữ gì để tìm nguyên nhân. Profile quy chiếu waiting time theo sample semantics, không tự là toàn request timeline.

## Hiểu cơ chế từ kết quả quan sát

Bật sampling có overhead và phạm vi; network chờ hay DB latency không phải lúc nào hiện như một channel block tại code bạn mong. Kết hợp goroutine stacks và execution trace để phân biệt waiting reason. Không coi thiếu block samples là chứng minh không có latency.

## Khái niệm và mô hình làm việc

Block profile ghi thời gian chờ synchronization events như channel và locks khi được enable.

## Cơ chế và những ranh giới cần giữ

SetBlockProfileRate điều khiển sampling; đọc blocking site/callers. Không coi nó là toàn bộ network/OS I/O wait profile.

## Áp dụng vào hệ thống thật

Pipeline kẹt output send khi downstream slower.

## Những đường lỗi cần hiểu

Capture trước khi enable không có history; long permanent wait có thể cần goroutine snapshot để thấy rõ.

## Lần theo bằng chứng khi có sự cố

So channel queue metrics, waiter stacks và execution trace.

## Đánh đổi và giới hạn sử dụng

Overhead phụ thuộc rate; capture ngắn theo hypothesis.

## Thực hành, debugging và kết luận

Thu một cửa sổ đại diện, ghi config sampling rồi tắt/giảm khi xong. Test backpressure và shutdown paths nơi stack chỉ tới. Sửa queue protocol hoặc giảm critical wait, xác nhận throughput/P99 cùng offered load.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)

## Thực hành có điều kiện kiểm chứng

Từ lab package, capture `go test -run TestPoolCancellation -blockprofile=block.out`, rồi `go tool pprof -top block.out`. Chờ ctx.Done trong test là expected wait, không leak; giải thích owner nào đóng signal. Trong production, chọn rate và duration trước capture; compare với goroutine snapshot để thấy waiters chưa hoàn tất trong cửa sổ sample.
