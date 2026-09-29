# Livelock và retry synchronization

## Bài toán và ví dụ đầu tiên

Hai worker cùng thử giành tài nguyên, thất bại thì cùng nhường rồi thử lại ngay. CPU và số attempt tăng nhưng không job nào hoàn tất. Livelock khác deadlock ở chỗ actor vẫn hoạt động; vấn đề là không có tiến triển có ích.

## Đi từng bước qua một tình huống

Một retry loop nhận 429 rồi lập tức gửi lại có thể duy trì overload khiến mọi lần thử tiếp tục nhận 429. Thêm khoảng nghỉ tăng dần và jitter — phần ngẫu nhiên làm các client lệch nhịp — giúp giảm đợt thử lại đồng loạt. Vẫn phải có trần attempts và deadline để việc thất bại cuối cùng được biểu diễn rõ.

## Hiểu cơ chế từ kết quả quan sát

TryLock trong for không tự tạo một lock hiệu quả hơn Mutex.Lock. Nó có thể quay vòng, gây cache contention và lấy CPU khỏi goroutine đang giữ lock vốn cần chạy để mở khóa. Scheduler fairness không đảm bảo thuật toán phối hợp sẽ tạo progress nếu logic luôn đưa actors về cùng trạng thái thất bại.

## Khái niệm và mô hình làm việc

Livelock vẫn hoạt động nhưng không tạo progress, thường do retry/coordination lặp cùng pattern.

## Cơ chế và những ranh giới cần giữ

Hai actors nhường nhau đồng thời hoặc CAS/retry loop lặp; khác deadlock ở chỗ CPU/counters còn tăng.

## Áp dụng vào hệ thống thật

Dùng bounded retry với jitter và deadline, atomic state transition rõ.

## Những đường lỗi cần hiểu

TryLock loop spin dưới contention; retry ngay sau 429 khiến overload tồn tại.

## Lần theo bằng chứng khi có sự cố

Đo attempts/s so completions/s, CPU hot loop và retry histogram.

## Đánh đổi và giới hạn sử dụng

Backoff tăng latency nhưng giảm synchronized contention; phải có stop budget.

## Thực hành, debugging và kết luận

Đo attempts/s song song completions/s và CPU profile. Attempts tăng mạnh trong khi completions bằng zero là dấu hiệu để kiểm tra loop và chính sách retry. Backoff có giá trị khi xung đột tạm thời; lỗi permanent phải trả lỗi thay vì thử mãi. Khi cần thứ tự rõ, một coordinator hoặc queue hữu hạn dễ suy luận hơn nhiều vòng CAS cạnh tranh.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)

## Thực hành có điều kiện kiểm chứng

Hai workers dùng TryLock, fail thì nhường rồi retry tức thì. Trong load test, ghi attempts và completions: attempts tăng mạnh nhưng completions gần0 là bằng chứng thiếu progress. Thêm bounded backoff+jitter rồi so throughput và fairness; nếu invariant chỉ cần một lock, blocking Lock thường đơn giản hơn loop tự chế. Cancel phải ngắt cả backoff để shutdown không đợi vô hạn.
