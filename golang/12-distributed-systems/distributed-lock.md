# Leases, locks và fencing tokens

## Bài toán và ví dụ đầu tiên

Hai worker cùng muốn migrate một tài nguyên. Redis/etcd lock có lease giúp chọn một owner tạm thời, nhưng worker cũ có thể pause lâu rồi tiếp tục sau khi lease đã hết và worker mới được cấp quyền. Lock name duy nhất chưa ngăn stale owner ghi dữ liệu.

## Đi từng bước qua một tình huống

Owner A có lease version 10, pause; lease hết, B nhận version 11 và ghi. A tỉnh lại vẫn tưởng mình sở hữu. Fencing token tăng theo authority được gửi tới storage, storage từ chối token cũ, mới ngăn A ghi sau B nếu hệ thống đích hỗ trợ kiểm tra đó.

## Hiểu cơ chế từ kết quả quan sát

Release lock phải kiểm tra owner token để A không xóa lock mới của B. TTL, clock assumptions và network partitions ảnh hưởng liveness/safety. Một mutex Go chỉ bảo vệ trong process; distributed lease có failure model rộng hơn. DB unique constraint hoặc conditional update có thể đơn giản hơn nếu invariant nằm ngay trong DB.

## Khái niệm và mô hình làm việc

Distributed lock có timeout/lease; old holder có thể tiếp tục chạy sau lease hết vì pause/network partition.

## Cơ chế và những ranh giới cần giữ

Target resource cần monotonic fencing token và reject stale owner. Random unlock token chống xóa lease người khác nhưng không xếp thứ tự writes.

## Áp dụng vào hệ thống thật

Single migration coordinator dùng lease và DB checkpoint version guard.

## Những đường lỗi cần hiểu

Stop-the-world/host pause dài hơn lease; lease renewed nhưng response mất; split-brain writer.

## Lần theo bằng chứng khi có sự cố

Audit owner epochs và accepted target writes; simulate delayed old owner.

## Đánh đổi và giới hạn sử dụng

Dùng unique constraints/CAS/transactions khi invariant nằm một DB; lock distributed thêm failure modes.

## Thực hành, debugging và kết luận

Test pause vượt lease, renew failure và delayed write sau lease loss. Theo dõi lease owner, fencing version và write rejection. Nếu resource đích không thể fence, cần thiết kế idempotent/versioned operation hoặc owner duy nhất có recovery, không tuyên bố lock đã bảo đảm tuyệt đối.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://etcd.io/docs/v3.6/learning/api/)
