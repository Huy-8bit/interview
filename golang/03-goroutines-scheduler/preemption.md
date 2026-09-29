# Preemption và safe points

## Bài toán và ví dụ đầu tiên

Một goroutine chạy vòng tính toán dài không chờ channel. Runtime vẫn cần cho goroutine khác cơ hội chạy, ví dụ handler trả health check. Preemption là việc tạm lấy lượt thực thi rồi sau đó có thể tiếp tục goroutine cũ từ trạng thái được lưu.

## Đi từng bước qua một tình huống

A tính liên tục, B đã runnable. Khi A được preempt ở điều kiện phù hợp, scheduler có thể chạy B. A chưa bị hủy và dữ liệu nghiệp vụ của nó chưa được rollback; nó chỉ mất lượt CPU tạm thời. Nếu muốn A dừng vì request hết hạn, A còn phải kiểm tra context và return.

## Hiểu cơ chế từ kết quả quan sát

Go dùng các safe point và cơ chế asynchronous preemption trên nền tảng hỗ trợ; vùng runtime nhạy cảm có giới hạn riêng. Không có hard real-time guarantee cho deadline của một goroutine. Cgo, syscall và lock contention còn ảnh hưởng tiến triển ngoài bài toán chia lượt CPU.

## Khái niệm và mô hình làm việc

Preemption cho scheduler cơ hội chạy G khác khi một G dùng CPU lâu.

## Cơ chế và những ranh giới cần giữ

Cooperative safe points và asynchronous mechanisms phụ thuộc architecture/runtime. STW, stack scan và unsafe runtime regions có ràng buộc riêng.

## Áp dụng vào hệ thống thật

CPU-heavy parsing cần bound payload và concurrency, không dựa vào preemption để có deadline cứng.

## Những đường lỗi cần hiểu

Vòng default-select spin dùng toàn core; cancel context không được kiểm tra trong tight compute loop.

## Lần theo bằng chứng khi có sự cố

CPU profile tìm loop; execution trace xem runnable latency, GC pauses và quota throttling.

## Đánh đổi và giới hạn sử dụng

Chia compute thành chunks để kiểm tra cancel nhưng đo overhead; runtime không phải real-time scheduler.

## Thực hành, debugging và kết luận

Khi tail latency cao cùng CPU saturation, dùng trace xem runnable delay và CPU profile xem vòng tính toán nào chiếm thời gian. Chia công việc thành chunk có điểm cancellation hữu ích cho responsiveness, nhưng gọi Gosched khắp nơi không thay thế thuật toán hiệu quả hoặc concurrency bound.


## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
