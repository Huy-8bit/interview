# Table-driven tests và subtests

## Bài toán và ví dụ đầu tiên

Một parser cần xử lý nhiều input edge cases cùng cách assert. Table-driven tests dùng danh sách cases có tên, input và expected result để giữ test ngắn nhưng vẫn giải thích từng tình huống.

## Đi từng bước qua một tình huống

Đặt tên như empty_input, missing_field, boundary_limit thay vì case1. Mỗi subtest có fixture độc lập nếu mutate state. Nếu chạy parallel, tránh dùng chung mutable map/server state; closure capture semantics còn phụ thuộc phiên bản ngôn ngữ và cách khai báo biến.

## Hiểu cơ chế từ kết quả quan sát

Table phù hợp khi các case có cùng hành vi kiểm tra. Nhét success, retry workflow và shutdown nhiều bước vào một table có hàng chục flag làm test khó đọc; dùng test riêng cho những timeline khác nhau. Expected errors nên dùng identity/type khi contract là errors.Is/As.

## Khái niệm và mô hình làm việc

Cases là data, mỗi case có expected behavior riêng dễ mở rộng edge coverage.

## Cơ chế và những ranh giới cần giữ

t.Run names mô tả scenario; t.Parallel chỉ khi fixtures không shared mutable. Loop variable capture semantics phụ thuộc module language version cho code cũ.

## Áp dụng vào hệ thống thật

Cases nil/empty/max/invalid và errors.Is expected cause.

## Những đường lỗi cần hiểu

Parallel tests dùng same temp DB row; old loop capture bug; one failure hides remaining cases.

## Lần theo bằng chứng khi có sự cố

Run -shuffle=on -count=20 targeted suite khi nghi order dependence.

## Đánh đổi và giới hạn sử dụng

Table quá nhiều logic branches khó đọc hơn tests riêng cho workflows khác nhau.

## Thực hành, debugging và kết luận

Kiểm tra failure output chỉ rõ case và giá trị khác nhau. Thêm case từ bug thực và boundary reasoning, không chỉ nhiều input ngẫu nhiên tương đương. Giữ fixture setup đủ đơn giản để người đọc tin test đang kiểm tra đúng điều nó mô tả.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

Đặt cases LowerBound gồm nil, target trước first, equal duplicate, giữa values và sau last. Assert first matching index và partition invariant, không chỉ result ở typical input. Nếu t.Parallel, mỗi case phải có fixture riêng hoặc immutable; schema shared cần unique namespace. Module language version1.22+ thay loop variable capture semantics, nhưng data referenced bên trong case vẫn có thể shared.
