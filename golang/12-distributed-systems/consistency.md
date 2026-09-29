# Consistency models và client observations

## Bài toán và ví dụ đầu tiên

User vừa đổi tên rồi refresh và thấy tên cũ từ replica. Dữ liệu chưa chắc mất; read có thể tới bản sao chưa nhận write. Consistency mô tả kết quả quan sát nào hợp lệ khi nhiều clients đọc/ghi, khác durability của write đã commit.

## Đi từng bước qua một tình huống

Linearizability yêu cầu operation có thể được xem như xảy ra tại một điểm giữa call và return, tôn trọng thứ tự thời gian thực. Read-your-writes là nhu cầu cụ thể của một client thấy write của mình. Eventual consistency cho phép các bản sao tạm khác rồi hội tụ dưới assumptions của hệ thống.

## Hiểu cơ chế từ kết quả quan sát

Chọn routing primary, version token hoặc session affinity có thể đáp ứng read-after-write theo thiết kế, nhưng cần xét failover. Cache TTL giới hạn một dạng tuổi dữ liệu nếu cơ chế invalidation/delivery giữ đúng assumptions, không tự tạo linearizable reads. Invariant tiền/quyền thường cần yêu cầu mạnh hơn presence online.

## Khái niệm và mô hình làm việc

Linearizability tôn trọng real-time order của operations; eventual consistency hứa convergence dưới assumptions, không hứa read mới ngay.

## Cơ chế và những ranh giới cần giữ

Read-your-writes và monotonic reads là session guarantees; quorum formulas cần assumptions về membership, versioning và failures.

## Áp dụng vào hệ thống thật

Sau tạo order, route read tới writer hoặc trả committed representation để tránh replica lag.

## Những đường lỗi cần hiểu

Read replica trả not-found sau successful write; stale config overwrites newer version.

## Lần theo bằng chứng khi có sự cố

Trace write/read versions, replica lag và client session routing.

## Đánh đổi và giới hạn sử dụng

Strong read tăng coordination latency; stale reads chỉ khi product cho phép.

## Thực hành, debugging và kết luận

Viết ví dụ UX cụ thể rồi xác định stale bao lâu được phép. Test write rồi read qua replica/cache trong tình huống delay và failover. Đo freshness/lag bên cạnh availability, vì HTTP200 với dữ liệu quá cũ vẫn có thể vi phạm mục tiêu sản phẩm.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.cs.cornell.edu/andru/cs711/2002fa/reading/linearizability.pdf)
