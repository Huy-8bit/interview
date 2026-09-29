# Ownership qua toàn lifecycle

## Bài toán và ví dụ đầu tiên

Một engineer thấy query chậm thuộc service team khác nhưng đang làm endpoint mình lỗi. Ownership là theo vấn đề tới khi có owner và kết quả rõ, đồng thời tôn trọng quyền quyết định của người vận hành hệ thống liên quan.

## Đi từng bước qua một tình huống

Bạn có thể tập hợp trace/query evidence, đề xuất mitigation có rollback, liên hệ owner qua quy trình team và theo dõi tới verification. Không tự thay production của team khác chỉ vì muốn nhanh. Nếu chưa có quyền, làm phương án concrete và nêu rủi ro/phụ thuộc để quyết định được đưa ra.

## Hiểu cơ chế từ kết quả quan sát

Ownership không là nhận mọi việc vào mình. Delegation rõ outcome, handoff có context và theo dõi follow-through giúp hệ thống bền hơn một cá nhân. Action item cần owner, thời hạn hợp lý và test/metric chứng minh hoàn thành, thay vì chỉ trạng thái ticket done.

## Khái niệm và mô hình làm việc

Ownership gồm làm rõ yêu cầu, delivery, monitoring, incident follow-up và bảo trì, không ôm mọi việc một mình.

## Cơ chế và những ranh giới cần giữ

Xác định decision owner và dependencies; communicate risk sớm, phân công action có deadline, theo dõi closure.

## Áp dụng vào hệ thống thật

Story minh họa: phát hiện pool exhaustion, mitigate admission, sửa Rows leak, thêm alert/test và review rollout.

## Những đường lỗi cần hiểu

Hero firefighting nhưng không systemic fix; nhận mọi task rồi bottleneck cả team.

## Lần theo bằng chứng khi có sự cố

Chuẩn bị bằng timeline/action artifacts và metric trước/sau; không bịa số khi không nhớ.

## Đánh đổi và giới hạn sử dụng

Escalate đúng lúc là ownership; tự giải quyết mọi thứ không luôn hiệu quả.

## Thực hành, debugging và kết luận

Khi kể ví dụ thật, mô tả vấn đề bạn phát hiện, phạm vi bạn quyết định và phần team hỗ trợ. Nêu cách tránh tái diễn qua bound/alert/test, không chỉ thời gian làm thêm. Kết quả tốt bao gồm vận hành sau khi bạn rời ca trực.


## Đọc tiếp

- [star-method](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)
