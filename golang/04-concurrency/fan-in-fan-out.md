# Fan-in và fan-out

## Bài toán và ví dụ đầu tiên

Một endpoint lấy thông tin từ ba nguồn độc lập. Fan-out chia công việc cho nhiều worker; fan-in gom các kết quả về một nơi để assemble response. Latency có thể giảm từ tổng thời gian các nguồn xuống gần nhánh chậm nhất, nhưng số lời gọi đồng thời tăng.

## Đi từng bước qua một tình huống

Nếu A hoàn tất sau 10 ms, C sau 20 ms, B sau 100 ms, output nhận theo completion có thứ tự A,C,B dù input là A,B,C. Muốn trả đúng thứ tự input, gắn index rồi ghi vào vị trí độc lập hoặc reorder tại coordinator. Nếu mọi worker cùng append vào một slice thì cần lock hoặc chỉ một goroutine sở hữu append.

## Hiểu cơ chế từ kết quả quan sát

Nhiều worker gửi chung output không được tự close output khi riêng mình xong: worker khác có thể vẫn đang send. Coordinator chờ tất cả producers hoàn tất rồi close. Khi consumer dừng sớm, mỗi producer phải có đường send bị hủy để không giữ cả nhóm ở Wait. Nhận lỗi đầu tiên không thay thế việc join các nhánh còn lại.

## Khái niệm và mô hình làm việc

Fan-out phân work nhiều workers; fan-in hợp outputs và đóng output khi mọi producer kết thúc.

## Cơ chế và những ranh giới cần giữ

Một coordinator Wait rồi close, không từng worker tự close shared output. Order không tự giữ sau parallel execution; gắn sequence khi cần reorder bounded.

## Áp dụng vào hệ thống thật

Fetch nhiều independent resources với per-request fan-out limit và global dependency limit.

## Những đường lỗi cần hiểu

100 calls mỗi request nhân 1000 requests tạo 100k operations; reorder buffer bị giữ bởi một slow item.

## Lần theo bằng chứng khi có sự cố

Đo fan-out width, aggregate deadline, slowest branch và output wait.

## Đánh đổi và giới hạn sử dụng

Parallel giảm latency nhưng tăng downstream load và failure surface; batch API có thể tốt hơn.

## Thực hành, debugging và kết luận

Giới hạn cả fan-out mỗi request và concurrency tổng tới dependency. Một limit 10/request vẫn thành 10000 calls ở 1000 request. Trace cần cho thấy từng nhánh và điểm join; P99 thường chịu nhánh chậm nhất. Nếu response chấp nhận phần thiếu, biểu diễn partial result rõ thay vì âm thầm bỏ nhánh lỗi.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
