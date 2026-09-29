# Backpressure: 10k vào, 5k ra

## Bài toán và ví dụ đầu tiên

Producer gửi 10000 job/s nhưng consumer chỉ xử lý 5000 job/s. Queue tăng 5000 job mỗi giây; queue 50000 chỗ chỉ mua khoảng 10 giây theo giả định tốc độ không đổi. Backpressure là cơ chế khiến phía tạo việc cảm nhận giới hạn phía xử lý, để hệ thống không tiếp tục nhận vô hạn.

## Đi từng bước qua một tình huống

Trong Go, channel hữu hạn đầy làm send chờ. Chờ đó cần context để caller hết deadline thoát được. Ở HTTP boundary, có thể reject sớm với policy quá tải. Ở Kafka consumer, có thể giảm lấy thêm/điều tiết theo API client trong khi vẫn giữ nghĩa vụ group protocol. Với workload không được mất, lưu bền và trả accepted chỉ sau khi đã nhận trách nhiệm durable.

## Hiểu cơ chế từ kết quả quan sát

Có ba budget khác nhau: số job, tổng bytes và thời gian chờ. 100 job mỗi job 1 KB khác 100 job mỗi job 100 MB. Queue còn chỗ chưa có nghĩa nên nhận job sẽ hết deadline trước khi bắt đầu. Admission control là quyết định nhận/từ chối dựa capacity và policy, có thể theo tenant để một khách không chiếm hết backlog.

Backpressure phải truyền qua toàn pipeline. Nếu stage A bị chặn gửi nhưng handler vẫn spawn một goroutine mới cho mọi input, hàng chờ đã chuyển từ channel sang goroutine stack. Nếu retry topic chỉ chuyển record giữa nhiều queue vô hạn, debt chưa biến mất. Cần bound tại nơi sở hữu dữ liệu và đo completion thật.

## Khái niệm và mô hình làm việc

Khi arrival 10k/s và completion 5k/s, backlog tăng 5k/s; queue hữu hạn chỉ mua thời gian.

## Cơ chế và những ranh giới cần giữ

Với payload 2KiB, thêm khoảng 9.8MiB/s trước overhead. Bound queue count/bytes, producer admission, consumer in-flight và retries. Scale chỉ khi sink còn headroom và partitions cho phép.

## Áp dụng vào hệ thống thật

API reject 429/503 khi vượt latency budget; broker durable giữ work với retention và oldest-age SLO.

## Những đường lỗi cần hiểu

Unbounded Go channels qua wrapper/list; spawn one G mỗi queued task; scale consumers làm target DB chậm hơn.

## Lần theo bằng chứng khi có sự cố

Đo rates, lag derivative, oldest age, queue bytes, active workers và DB wait; recovery phải có service rate > arrival.

## Đánh đổi và giới hạn sử dụng

Drop phù hợp telemetry best-effort, không money; load shedding cần product contract.

## Thực hành, debugging và kết luận

Production khi downstream chậm nên ưu tiên giữ số in-flight hữu hạn, shed công việc có policy và làm recovery không tạo burst mới. Đo arrival/accepted/completed/rejected cùng queue age/bytes. Queue depth giảm vì drop hàng loạt không được báo như throughput tăng.

Test overload dài hơn thời gian buffer có thể hấp thụ. Xác nhận memory đạt plateau hợp lý, cancellation trả tài nguyên và công việc được nhận có outcome rõ. Tăng capacity xử lý chỉ đúng khi bottleneck còn có thể song song; nếu một global lock hoặc DB serialize, thêm workers chỉ tăng phần chờ.



## Tính budget cho một queue cụ thể

Một worker pool8 workers xử lý trung bình mỗi job80ms, capacity lý tưởng khoảng100 job/s khi không có bottleneck khác. Queue200 jobs có thể chứa khoảng2giây công việc ở tốc độ đó. Nếu deadline còn500ms, nhận thêm job khi queue gần đầy thường chỉ giữ payload rồi trả timeout trước khi job tạo giá trị. Admission có thể từ chối sớm hoặc chuyển thành durable async contract thay vì giả vờ mọi request được xử lý ngay.

Giả sử payload mỗi job20KB trung bình nhưng có tail5MB. Cap200 phần tử không cho một hard memory bound20KB×200 vì distribution có tail. Giới hạn bytes hoặc chuẩn hóa queue chỉ giữ object references/IDs tới storage bền; worker fetch payload khi có slot và áp size limit. Concurrency count, queue bytes và max item size phối hợp mới cho memory model hữu ích.

Khi sink DB chỉ chịu50 writes/s,8 workers không còn capacity100/s như tính ban đầu. Queue đầy nhanh hơn, acquire pool wait tăng và average job time đổi. Backpressure là vòng phản hồi theo capacity thực, nên measurements phải cập nhật khi dependency chậm. Tăng queue từ200 lên20000 không thay50/s, chỉ kéo dài thời gian user chờ và làm recovery lâu hơn.

Test nên giữ input vượt capacity đủ lâu, kiểm tra accepted/rejected theo policy, max memory và job age. Sau khi hạ input dưới capacity, backlog phải giảm với tốc độ gần completed-arrival theo giả định ổn định; nếu không, có thể retry churn hoặc poison jobs. Đo tiến triển hữu ích thay vì chỉ số attempts để không nhầm hệ thống bận với hệ thống xử lý được việc.

## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)
