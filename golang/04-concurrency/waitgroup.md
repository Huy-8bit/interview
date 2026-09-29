# WaitGroup: join và lifecycle

## Bài toán và ví dụ đầu tiên

Main tạo ba worker rồi phải đóng database sau khi cả ba dừng. Một biến boolean cannot diễn đạt có bao nhiêu worker còn sống. WaitGroup là bộ đếm công việc chưa hoàn tất; Wait chặn caller đến khi bộ đếm trở về zero.

## Đi từng bước qua một tình huống

Owner gọi Add(3) trước khi launch hoặc Add(1) ngay trước từng go statement. Mỗi worker defer Done để mọi đường return đều giảm đúng một lần. Nếu Add nằm bên trong goroutine, owner có thể gọi Wait khi bộ đếm còn zero và tiếp tục đóng DB trước khi worker bắt đầu. Đây là lỗi lifecycle dù code có vẻ đủ ba method.

## Hiểu cơ chế từ kết quả quan sát

WaitGroup không chứa result, không giữ error và không phát cancellation. Nếu worker mắc ở channel send, Wait chỉ chờ mãi. Muốn dừng nhóm, phát tín hiệu qua context trước, đảm bảo worker quan sát, rồi Wait. Muốn close output chung, một coordinator Wait tất cả producer xong rồi close; không để từng producer tự close.

## Khái niệm và mô hình làm việc

WaitGroup đếm tasks chưa hoàn tất, không truyền results hoặc errors.

## Cơ chế và những ranh giới cần giữ

Add trước launch để tránh Wait thấy zero quá sớm; worker defer Done. Không copy sau use; reuse chỉ khi lần Wait trước đã return. Go 1.25 thêm WaitGroup.Go với contract riêng về panic.

## Áp dụng vào hệ thống thật

Coordinator đợi producers xong rồi close output; error propagation qua channel/context hoặc errgroup có bound.

## Những đường lỗi cần hiểu

Add trong child race với Wait; thiếu Done khiến shutdown treo; negative counter panic.

## Lần theo bằng chứng khi có sự cố

Dùng done signal và timeout trong test; xem stack Wait cùng worker còn blocked.

## Đánh đổi và giới hạn sử dụng

WaitGroup cho join đơn giản; errgroup hữu ích khi cần error/cancel nhưng dependency có version.

## Thực hành, debugging và kết luận

Khi shutdown treo, xem worker đang chờ tài nguyên nào; đừng xóa Wait để che lỗi. Test dùng started channel để biết worker đã vào điểm chờ rồi cancel và xác nhận finished. Không copy WaitGroup sau dùng và chỉ reuse sau khi đợt Wait trước đã hoàn tất. API WaitGroup.Go có ở Go mới hơn baseline của lab; phải kiểm tra phiên bản và contract panic trước khi chuyển cú pháp.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
