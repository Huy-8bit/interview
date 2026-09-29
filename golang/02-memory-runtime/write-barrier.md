# Write barrier và concurrent marking

## Bài toán và ví dụ đầu tiên

GC đang đánh dấu object sống trong lúc ứng dụng vẫn sửa pointer. Nếu collector đã scan một object rồi ứng dụng chuyển một reference mới vào đó, collector cần cơ chế giữ invariant để không bỏ sót object còn sống. Write barrier hỗ trợ việc ghi pointer trong giai đoạn thích hợp.

## Đi từng bước qua một tình huống

Hình dung collector đã đi qua A, còn B chưa được xét. Application thay một cạnh trong object graph để A trỏ tới B. Nếu mọi thay đổi đều vô hình với collector, thuật toán mark đơn giản có thể suy luận sai. Barrier bổ sung bookkeeping theo thuật toán runtime để việc mutation không phá tính đúng.

## Hiểu cơ chế từ kết quả quan sát

Màu trắng/xám/đen là mô hình đối tượng chưa đánh dấu, đã biết cần scan và đã scan. Nó diễn giải proof của collector, không phải state nghiệp vụ và không cần xuất hiện trong code ứng dụng. Go dùng barrier cụ thể theo runtime; không biến sơ đồ tricolor đơn giản thành mô tả mọi instruction của release hiện tại.

## Khái niệm và mô hình làm việc

Write barrier giúp GC theo dõi pointer mutations trong concurrent mark, không phải mutex cho application.

## Cơ chế và những ranh giới cần giữ

Tri-color reasoning: nếu graph đổi lúc scan, barrier duy trì invariant cần thiết để object reachable không bị bỏ sót. Exact hybrid barrier phụ thuộc runtime version.

## Áp dụng vào hệ thống thật

Pointer-rich cache churn có thể tăng GC work; value arrays ít pointers có scan cost khác.

## Những đường lỗi cần hiểu

Bỏ synchronization vì tưởng barrier bảo vệ dữ liệu tạo race; unsafe pointer manipulation phá assumptions.

## Lần theo bằng chứng khi có sự cố

CPU profile tìm GC/barrier-related work, xem pointer density và allocation rate trước khi sửa layout.

## Đánh đổi và giới hạn sử dụng

Không tự tắt barrier; giảm churn và đo representation khi memory profile chỉ ra bottleneck.

## Thực hành, debugging và kết luận

Barrier không là mutex và không tạo quyền sửa map đồng thời. Nếu CPU profile có nhiều GC/barrier work, xem allocation và churn của graph nhiều pointer. Dùng unsafe để né barrier có thể phá assumptions của runtime; ưu tiên thiết kế dữ liệu và ownership rõ rồi đo tác động.


## Đọc tiếp

- [Garbage collection: live heap, pacing và memory budget](garbage-collector.md)
- [Escape analysis: đọc quyết định của compiler](escape-analysis.md)
- [memory-profile](../16-performance/memory-profile.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/gc-guide)
