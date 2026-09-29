# Technical disagreement và evidence

## Bài toán và ví dụ đầu tiên

Hai engineer bất đồng dùng Kafka hay job table. Conflict kỹ thuật có thể đến từ assumptions khác nhau về replay, volume hoặc năng lực vận hành, không phải một bên không hiểu công nghệ.

## Đi từng bước qua một tình huống

Viết requirements và failure semantics trước, so hai option theo throughput, replay window, ordering, cost và on-call. Một spike nhỏ có thể kiểm chứng bottleneck; nếu deadline gấp, chọn decision có thể đảo ngược với trigger revisit rõ. Ghi phần đồng thuận và phần chưa chắc.

## Hiểu cơ chế từ kết quả quan sát

Lắng nghe constraint của bên khác giúp tránh tranh luận bằng danh tiếng tool. Decision owner chịu trách nhiệm chọn khi đã đủ evidence, còn người bất đồng có thể commit thực hiện trong scope quyết định và ghi risk có căn cứ. Không sửa kết quả lịch sử để câu chuyện bản thân luôn đúng.

## Khái niệm và mô hình làm việc

Conflict tốt tập trung constraints/invariants và cách kiểm chứng, không cá nhân hay preference ngôn ngữ.

## Cơ chế và những ranh giới cần giữ

Restate goal chung, steelman alternative, thử experiment nhỏ, thống nhất criteria và decision owner. Record revisit condition.

## Áp dụng vào hệ thống thật

Ví dụ giả định: sync.Map versus mutex; benchmark hot-key/read-write workload và chọn đơn giản hơn khi không có benefit.

## Những đường lỗi cần hiểu

Cherry-pick benchmark, kéo dài tranh luận không deadline, dismiss junior concern.

## Lần theo bằng chứng khi có sự cố

Chuẩn bị lúc bạn đổi ý và điều evidence chứng minh; outcome có thể là alignment hơn performance.

## Đánh đổi và giới hạn sử dụng

Không mọi disagreement cần prototype; rủi ro/chi phí quyết định effort.

## Thực hành, debugging và kết luận

Kể một ví dụ thật với lập luận của cả hai phía, evidence làm bạn đổi hoặc giữ quan điểm và outcome sau đó. Kỹ năng được thể hiện ở chất lượng quyết định/quan hệ làm việc, không ở việc thắng mọi tranh luận.


## Đọc tiếp

- [star-method](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)
