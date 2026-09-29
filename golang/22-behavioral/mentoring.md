# Mentoring tăng autonomy

## Bài toán và ví dụ đầu tiên

Junior sửa goroutine leak bằng thêm Sleep vì test thỉnh thoảng fail. Mentoring không chỉ đưa patch đúng mà giúp người học hiểu vì sao cần tín hiệu completion để lần sau tự giải quyết lifecycle tương tự.

## Đi từng bước qua một tình huống

Cùng dựng timeline caller return và worker send, yêu cầu một invariant về kết thúc, rồi viết test với started/finished channels. Mentor giải thích cancellation khác join và để người học triển khai bản sửa, review reasoning chứ không chỉ syntax.

## Hiểu cơ chế từ kết quả quan sát

Mức hỗ trợ thay đổi theo rủi ro/task: production incident có thể cần hướng dẫn trực tiếp trước, sau đó debrief; bài luyện có thể để thử và quan sát. Feedback cụ thể về hành vi/code, tránh gắn lỗi với năng lực cố định của người học.

## Khái niệm và mô hình làm việc

Mentoring giúp người học reasoning và tự sửa lỗi, không chỉ nhận đáp án/code đã viết hộ.

## Cơ chế và những ranh giới cần giữ

Hỏi invariant, cùng debug một case, đưa feedback cụ thể rồi giao ownership tăng dần. Tạo safe review và follow-up.

## Áp dụng vào hệ thống thật

Ví dụ giả định: junior viết fan-out leak; cùng vẽ lifetime, họ sửa cancel/join và dạy lại team.

## Những đường lỗi cần hiểu

Chỉ sửa code thay họ; feedback vague; gatekeeping technical knowledge.

## Lần theo bằng chứng khi có sự cố

Measure autonomy/review iteration/on-call readiness, không chỉ số buổi mentoring.

## Đánh đổi và giới hạn sử dụng

Pairing tốn thời gian trước mắt nhưng giảm dependency dài hạn; tailor theo skill gap.

## Thực hành, debugging và kết luận

Đánh giá tiến bộ bằng khả năng giải thích và xử lý case mới, không số comment mentor viết. Ghi tài liệu dùng lại và tạo cơ hội review hai chiều. Khi kể ví dụ, tôn trọng đồng nghiệp và không biến thành câu chuyện hạ thấp người được hỗ trợ.


## Đọc tiếp

- [star-method](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)
