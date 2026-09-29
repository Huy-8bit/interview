# STAR với technical evidence

## Bài toán và ví dụ đầu tiên

Một câu chuyện kỹ thuật có nhiều bối cảnh nhưng người nghe cần hiểu bạn chịu trách nhiệm gì và quyết định nào tạo kết quả. STAR là cấu trúc Situation, Task, Action, Result để tổ chức câu chuyện thật theo quan hệ nhân quả.

## Đi từng bước qua một tình huống

Ví dụ minh họa: backlog tăng làm checkout chậm; nhiệm vụ cá nhân là tìm bottleneck trong một ca trực; action gồm phân pool wait, giảm backfill concurrency và kiểm tra query giữ Tx; result là latency/backlog phục hồi theo số liệu thực của tình huống. Đây là ví dụ cách lập luận, không được kể như kinh nghiệm cá nhân nếu chưa từng làm.

## Hiểu cơ chế từ kết quả quan sát

Situation đủ để thấy impact, Task giới hạn vai trò, Action nêu reasoning/trade-off và phối hợp, Result ghi evidence cùng giới hạn. Tách đóng góp cá nhân với công sức team một cách trung thực. Reflection giải thích lần sau sẽ thay mechanism gì, không chỉ “giao tiếp tốt hơn”.

## Khái niệm và mô hình làm việc

Situation/Task/Action/Result giúp story có logic; thêm reflection để thể hiện learning.

## Cơ chế và những ranh giới cần giữ

S ngắn nêu impact, T nêu scope cá nhân, A chiếm phần lớn với decisions/trade-offs, R có evidence và limitations. Không mượn hypothetical story làm kinh nghiệm bản thân.

## Áp dụng vào hệ thống thật

Mẫu minh họa: S backlog tăng, T bảo vệ checkout, A bound backfill và fix Tx hold, R queue drain/P99 recovery; điền facts thật bằng lời kể của mình, không số liệu bịa.

## Những đường lỗi cần hiểu

Nói we toàn bộ không rõ contribution; outcome không gắn action; kể10 phút context.

## Lần theo bằng chứng khi có sự cố

Tự record2 và5 phút, nhờ reviewer hỏi sâu vào hypothesis/testing/rollback.

## Đánh đổi và giới hạn sử dụng

STAR là cấu trúc hỗ trợ, không script học thuộc; câu trả lời phải responsive câu hỏi.

## Thực hành, debugging và kết luận

Chuẩn bị phiên bản ngắn2 phút và dài5 phút từ facts thật, kiểm tra mỗi số liệu có nguồn bạn nhớ/được phép chia sẻ. Không cần học thuộc script; ưu tiên câu chuyện trả lời đúng phạm vi và có thể giải thích sâu một quyết định.


## Đọc tiếp

- [STAR với technical evidence](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)
