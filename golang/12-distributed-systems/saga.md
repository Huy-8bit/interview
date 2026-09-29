# Saga và compensating actions

## Bài toán và ví dụ đầu tiên

Đặt chuyến đi cần reserve vé và khách sạn ở hai service có database riêng. Vé đã giữ nhưng khách sạn thất bại. Không thể gọi Rollback trên một SQL transaction để quay ngược thay đổi đã commit ở service khác. Saga biểu diễn chuỗi local transactions và những hành động bù có ý nghĩa nghiệp vụ.

## Đi từng bước qua một tình huống

Workflow lưu trạng thái: started → flight_reserved → hotel_reserved → completed. Nếu hotel thất bại, chuyển sang cancelling_flight rồi cancelled khi hoàn trả thành công. Compensation như hủy giữ vé là một operation mới; nó có thể có phí, deadline hoặc thất bại tạm thời. Không coi compensation như undo mọi thứ về đúng thời điểm trước đó.

## Hiểu cơ chế từ kết quả quan sát

Orchestration dùng coordinator lưu state và ra lệnh; choreography để các service phản ứng với events. Coordinator làm luồng rõ nhưng cần durable state và recovery; choreography giảm một số coupling trực tiếp nhưng khiến toàn workflow khó theo dõi. Cả hai cần operation ID, idempotent commands, retry limits và xử lý message đến lặp/khác thứ tự.

Intermediate states có thể quan sát được: user thấy vé pending trong lúc hotel chưa xong. Đây không phải isolation như một transaction DB duy nhất. Thiết kế API/UI phải diễn đạt pending, compensating và manual-review, không báo success chỉ vì bước đầu thành công.

## Khái niệm và mô hình làm việc

Saga điều phối local transactions; compensation là business action bù, không rollback thời gian.

## Cơ chế và những ranh giới cần giữ

State machine persisted, commands/events idempotent, retries bounded; orchestrator giữ progress hoặc choreography có event contracts rõ.

## Áp dụng vào hệ thống thật

Order reserve stock → authorize payment → confirm; failure release reservation/void authorization theo policy.

## Những đường lỗi cần hiểu

Compensation fail; events out of order; double refund khi replay; irreversible external action.

## Lần theo bằng chứng khi có sự cố

Trace saga ID, state transitions, timeout age và reconciliation backlog.

## Đánh đổi và giới hạn sử dụng

Saga tăng availability nhưng exposed intermediate states; dùng một DB transaction nếu đủ boundary.

## Thực hành, debugging và kết luận

Test restart coordinator sau mỗi transition, lỗi compensation và duplicate command. Khi incident, query state theo saga ID và đối chiếu provider references; retry lại toàn workflow với ID mới có thể giữ thêm vé. Alert stuck state theo tuổi và business deadline.

Saga phù hợp workflow qua nhiều owner dữ liệu; nếu invariant có thể ở một DB transaction đơn giản thì giữ cùng boundary thường dễ đúng hơn. Chấp nhận eventual completion phải đi cùng owner vận hành và quy trình giải quyết trạng thái không thể tự phục hồi.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
