# CAP: quyết định trong network partition

## Bài toán và ví dụ đầu tiên

Hai replica bị mất liên lạc nhưng vẫn nhận request từ hai phía. Nếu cả hai nhận mọi write độc lập, chúng có thể không đồng ý về giá trị hiện tại. Nếu cần một thứ tự duy nhất nhất quán mạnh, một phía có thể phải từ chối hoặc chờ khi không xác nhận được authority.

## Đi từng bước qua một tình huống

CAP xét trade-off giữa consistency theo nghĩa linearizability và availability theo định nghĩa lý thuyết khi network partition xảy ra. Nó không phải menu chọn bất kỳ hai trong ba tính năng mỗi ngày. Partition là failure môi trường mà thiết kế phải đối mặt, không đơn giản là một tính năng có thể tắt.

## Hiểu cơ chế từ kết quả quan sát

Một hệ thống có thể chọn policy khác theo operation: balance mutation cần authority/quorum, presence có thể chấp nhận tạm khác. Khi mạng khỏe vẫn còn latency/consistency trade-offs; CAP không đủ để quyết định cache, transaction isolation hoặc toàn bộ architecture.

## Khái niệm và mô hình làm việc

CAP xét linearizable consistency và availability theo định nghĩa lý thuyết khi có partition; không phải chọn hai tính năng tùy ý mọi lúc.

## Cơ chế và những ranh giới cần giữ

Nếu replicas không giao tiếp được, trả lời mọi request có thể phá single-copy consistency; chờ/reject có thể giữ safety nhưng mất availability ở phần hệ thống.

## Áp dụng vào hệ thống thật

Balance update chọn authority/quorum, catalog read có thể stale theo contract.

## Những đường lỗi cần hiểu

Gọi eventual consistency là always available dù quorum/region failure vẫn khiến request fail.

## Lần theo bằng chứng khi có sự cố

Xác định operation, partition model và response guarantees trước gắn nhãn CP/AP.

## Đánh đổi và giới hạn sử dụng

CAP không tự quyết định latency trade-off khi network bình thường; nêu consistency model cụ thể.

## Thực hành, debugging và kết luận

Dựng tình huống hai phía cùng sửa một key rồi hỏi invariant nào phải giữ và response nào client nhận. Ghi policy khi mất quorum và khi reconcile. Tránh gắn nhãn AP/CP cho cả sản phẩm mà không chỉ rõ operation, failure model và semantics đang bàn.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://users.ece.cmu.edu/~adrian/731-sp04/readings/GL-cap.pdf)
