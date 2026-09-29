# Behavioral incident story

## Bài toán và ví dụ đầu tiên

Trong outage, người đọc cần hiểu ảnh hưởng, quyết định dưới thông tin thiếu và cách team phục hồi. Một câu chuyện incident không nên chỉ liệt kê lệnh đã chạy hoặc mô tả mình là người duy nhất cứu hệ thống.

## Đi từng bước qua một tình huống

Dựng timeline từ symptom đến hypothesis, evidence, mitigation và verification. Ví dụ mô phỏng pool cạn: stats/stack cho thấy Tx giữ qua network, giảm route concurrency để giảm impact rồi sửa lifecycle. Tách thông tin biết lúc đó với điều chỉ biết sau postmortem.

## Hiểu cơ chế từ kết quả quan sát

Một mitigation có thể chấp nhận latency/error một phần để bảo vệ dữ liệu; giải thích trade-off và ai thống nhất. Root cause thường có trigger và contributing factors như thiếu bounds hoặc probe cascade. Blameless không nghĩa bỏ trách nhiệm, mà tìm cơ chế làm lỗi dễ xảy ra và khó phát hiện.

## Khái niệm và mô hình làm việc

Incident story thể hiện judgment dưới áp lực và khả năng học sau recovery.

## Cơ chế và những ranh giới cần giữ

STAR: symptom/impact, role, mitigation hypotheses, coordination, recovery verification, root cause và prevention owners.

## Áp dụng vào hệ thống thật

Ví dụ giả định: traffic ổn nhưng P99 tăng, DB WaitDuration tăng; pause backfill rồi tìm long Tx và sửa query path.

## Những đường lỗi cần hiểu

Claim root cause từ correlation; thay nhiều thứ cùng lúc; quên thông báo impact hoặc verify backlog.

## Lần theo bằng chứng khi có sự cố

Tập kể 5 phút, giữ timeline và kết quả thực; phân biệt điều biết lúc incident với điều biết sau.

## Đánh đổi và giới hạn sử dụng

Speed mitigation và evidence preservation cần cân bằng theo severity.

## Thực hành, debugging và kết luận

Dùng incident thật đã được phép chia sẻ, ẩn chi tiết nhạy cảm. Nêu evidence recovery gồm SLO và backlog/unknown outcomes. Action sau incident nên có owner và regression scenario, không chỉ “cẩn thận hơn khi deploy”.


## Đọc tiếp

- [star-method](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)
