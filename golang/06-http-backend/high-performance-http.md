# HTTP performance có evidence

## Bài toán và ví dụ đầu tiên

Một benchmark /ping đạt RPS cao nhưng endpoint thật chậm vì DB và encode JSON lớn. Hiệu năng HTTP có ích phải đo throughput hoàn tất trong latency/error mục tiêu với payload và dependency giống thực tế.

## Đi từng bước qua một tình huống

Chạy baseline ở tải thấp để biết service time, tăng offered load từng mức để thấy khi queue delay bắt đầu tăng. Offered là số request gửi vào; completed là số hoàn tất. Một server trả lỗi rất nhanh có thể có RPS cao nhưng không phục vụ thêm công việc hữu ích.

## Hiểu cơ chế từ kết quả quan sát

Tối ưu theo bằng chứng: CPU profile cho serialization/tính toán, heap cho allocation/retention, trace và pool metrics cho chờ. Keep-alive giảm handshake, bounded concurrency bảo vệ downstream, body limits bảo vệ memory. Mỗi kỹ thuật giải quyết một nguồn chi phí khác nhau.

## Khái niệm và mô hình làm việc

Throughput bền vững phải giữ P99/error budget khi dependencies chịu tải thật.

## Cơ chế và những ranh giới cần giữ

Measure allocations, TLS/reuse, JSON, compression, DB wait; bound concurrency và payload trước micro-optimizations.

## Áp dụng vào hệ thống thật

Load ramp từ 1k tới 20k RPS với representative hot keys và payloads.

## Những đường lỗi cần hiểu

Load generator closed-loop che overload; pool tăng khiến DB saturate; compression CPU chi phối.

## Lần theo bằng chứng khi có sự cố

CPU/heap profiles và traces cùng load timestamps; phân biệt app CPU và upstream queuing.

## Đánh đổi và giới hạn sử dụng

Custom unsafe encoder chỉ sau benchmark và compatibility tests; thường reuse/batching/index hiệu quả hơn.

## Thực hành, debugging và kết luận

So trước/sau cùng protocol, payload distribution, connections, warmup và CPU quota. Báo P50/P99, errors và tài nguyên cùng throughput. Đừng thêm pool object hay custom parser khi profile không chỉ vào đó; độ phức tạp ownership có thể tạo corruption khó hơn chi phí ban đầu.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)
