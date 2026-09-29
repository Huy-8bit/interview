# Technical leadership không cần chức danh

## Bài toán và ví dụ đầu tiên

Một thay đổi reliability liên quan nhiều teams không có ai sở hữu toàn đường request. Leadership kỹ thuật tạo mục tiêu chung, chia trách nhiệm và giúp quyết định tiến triển dù không quản lý trực tiếp mọi người.

## Đi từng bước qua một tình huống

Bắt đầu từ user impact và metric, đề xuất phạm vi nhỏ có evidence, phân owner cho API, DB và rollout. Làm trade-off/rollback cụ thể để reviewer quyết định. Theo dõi dependencies và gỡ blocker bằng thông tin, không chỉ nhắc deadline.

## Hiểu cơ chế từ kết quả quan sát

Ảnh hưởng bền cần chia sẻ reasoning và tăng khả năng tự quyết của team. Nếu mọi thay đổi phải qua một senior duy nhất, bottleneck tổ chức tăng. Documentation/runbook và mentoring làm kiến thức không chỉ nằm trong đầu người dẫn.

## Khái niệm và mô hình làm việc

Leadership tạo clarity, alignment và khả năng ra quyết định của người khác.

## Cơ chế và những ranh giới cần giữ

Viết problem/invariants/options trong RFC ngắn, thu feedback từ stakeholders, quyết định và record dissent/triggers để revisit.

## Áp dụng vào hệ thống thật

Ví dụ minh họa: dẫn rollout expand-contract giữa API/DB teams, có rollback và compatibility gates.

## Những đường lỗi cần hiểu

Dùng authority thay evidence; design quá lớn không delivery; không chia credit.

## Lần theo bằng chứng khi có sự cố

Chuẩn bị quyết định có disagreement thật, evidence đã đổi ý bạn và cách đo adoption.

## Đánh đổi và giới hạn sử dụng

Consensus mọi chi tiết chậm; decision owner rõ nhưng lắng nghe evidence.

## Thực hành, debugging và kết luận

Khi trình bày kinh nghiệm, phân biệt quyết định bạn dẫn dắt với implementation của đồng đội, nêu tín hiệu đo kết quả và điều chưa đạt. Chọn câu chuyện có sự phối hợp/đánh đổi thật, không chỉ quy mô code đã viết.


## Đọc tiếp

- [star-method](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)

## Thực hành có điều kiện kiểm chứng

Chuẩn bị một story có decision date, criteria và stakeholder disagreement thật. Ví dụ minh họa rollout schema: bạn viết compatibility matrix, chia owners migrate/deploy/verify, đặt rollback trigger và theo dõi adoption. Khi kể kinh nghiệm của mình, thay bằng facts thực, nêu evidence khiến team đồng thuận hoặc khiến bạn đổi ý; không tự nhận toàn kết quả của team.
