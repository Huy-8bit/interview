# Buffered versus unbuffered

## Bài toán và ví dụ đầu tiên

Một producer đọc file theo burst còn consumer ghi DB đều đặn. Unbuffered channel buộc mỗi send gặp một receive. Buffered channel cho producer đi trước tối đa một số giá trị; sự khác nhau chính là nơi có thể chờ, không phải một loại luôn nhanh hơn loại kia.

## Đi từng bước qua một tình huống

Với capacity 2 và consumer chưa chạy, send A và B hoàn tất, send C chờ. Consumer nhận A thì C có thể vào queue. Với capacity 0, send A đã phải chờ. Trong cả hai trường hợp, producer không biết consumer đã commit A vào DB chỉ từ việc send hoàn tất; completion cần một response/ack sau xử lý.

## Hiểu cơ chế từ kết quả quan sát

Buffer lưu giá trị theo kiểu Go: một slice value chỉ giữ header và tham chiếu tới array. Hai job có thể giữ chung payload nếu producer reuse buffer, tạo corruption khi consumer xử lý sau. Phải copy hoặc chuyển ownership. Queue capacity đếm phần tử chứ không đếm byte; payload size biến thiên làm memory budget cần thêm giới hạn.

## Khái niệm và mô hình làm việc

Unbuffered rendezvous đồng bộ sender/receiver; buffered tách thời điểm gửi và nhận tối đa capacity.

## Cơ chế và những ranh giới cần giữ

Queue capacity C có thể hấp thụ burst nhưng nếu arrival > completion dài hạn thì sẽ đầy. Send success không phải ack processing.

## Áp dụng vào hệ thống thật

Chọn C từ tolerated queue wait và payload memory; dùng buffer 1 cho one-shot result nếu caller có thể timeout.

## Những đường lỗi cần hiểu

Tăng C giấu overload; producer không cancel làm shutdown treo khi queue đầy.

## Lần theo bằng chứng khi có sự cố

Đo queue age và rate, không chỉ len; test capacity 0,1 và full.

## Đánh đổi và giới hạn sử dụng

Unbuffered dễ reasoning handshake; buffered cải thiện burst nhưng thêm memory/latency.

## Thực hành, debugging và kết luận

Thử burst 100 job khi service chỉ hoàn tất 10 job/s. Queue hấp thụ burst nếu có đủ chỗ, nhưng job cuối vẫn đợi gần 10 giây theo giả định này. Đo tuổi job và deadline, không chỉ len(channel). Chọn buffer theo burst chấp nhận được và memory budget; overload kéo dài cần giảm đầu vào hoặc tăng capacity xử lý đã được kiểm chứng.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
