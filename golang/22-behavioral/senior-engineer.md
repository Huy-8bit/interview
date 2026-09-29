# Senior engineer: scope và judgment

## Bài toán và ví dụ đầu tiên

Senior backend engineer không chỉ biết tên runtime structs. Vai trò cần nối correctness, performance, vận hành và nhu cầu sản phẩm để chọn giải pháp có thể duy trì dưới failure.

## Đi từng bước qua một tình huống

Ví dụ cache chậm: senior xác định freshness contract, capacity fallback và owner invalidation trước khi thêm Redis. Với worker pool, họ xét producer lifetime, queue bytes và shutdown chứ không chỉ số workers. Kỹ thuật sâu có giá trị khi dẫn tới quyết định đúng trong context.

## Hiểu cơ chế từ kết quả quan sát

Judgment gồm biết assumptions nào chưa được đo, lựa chọn nào có thể đảo ngược và khi nào cần người sở hữu domain tham gia. Communication làm reviewer/on-call hiểu causal reasoning. Mentoring và documentation giúp team không phụ thuộc một cá nhân giải mọi incident.

## Khái niệm và mô hình làm việc

Senior được đánh giá qua cách giảm rủi ro, ra quyết định và giúp team delivery bền vững, không chỉ số năm hoặc syntax.

## Cơ chế và những ranh giới cần giữ

Giải thích context/constraints, alternatives, decision, measured outcome và lesson. Nêu contribution cá nhân tách kết quả tập thể.

## Áp dụng vào hệ thống thật

Ví dụ minh họa: chọn pool/admission tuning sau metrics thay rewrite service vì bottleneck DB wait.

## Những đường lỗi cần hiểu

Kể chỉ stack công nghệ; claim scale không có workload; đổ lỗi team khác.

## Lần theo bằng chứng khi có sự cố

Tự hỏi interviewer có thể kiểm chứng số liệu nào và trade-off nào mình sở hữu.

## Đánh đổi và giới hạn sử dụng

Depth hơn breadth: một incident giải thích rõ tốt hơn mười buzzwords.

## Thực hành, debugging và kết luận

Chuẩn bị evidence thật về một quyết định, một failure và một lần thay đổi quan điểm nhờ dữ liệu. Nêu limits của kết quả thay vì hứa tuyệt đối. Checklist thuật ngữ chỉ là bản đồ ôn lại sau khi đã hiểu mechanism, không thay kinh nghiệm và khả năng giải thích.


## Đọc tiếp

- [star-method](star-method.md)
- [full-mock-interview](../23-mock-interview/full-mock-interview.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://rework.withgoogle.com/intl/en/guides/hiring-use-structured-interviewing)
