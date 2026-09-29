# Fuzzing input space và invariants

## Bài toán và ví dụ đầu tiên

Parser nhận input khó liệt kê hết bằng tay. Fuzzing tạo và biến đổi nhiều input để tìm panic hoặc vi phạm property; property phải thể hiện điều đúng chung chứ không sao chép thuật toán đang test.

## Đi từng bước qua một tình huống

Với lower-bound trên sorted slice, kết quả phải trong [0,len], mọi phần tử trước nhỏ hơn target và phần tử tại vị trí nếu có không nhỏ hơn target. Đây là property độc lập với cách binary search cài đặt. Seed cases rỗng, duplicate và biên số giúp bắt đầu vùng hữu ích.

## Hiểu cơ chế từ kết quả quan sát

Fuzz input cần bound chi phí để một case không allocate quá lớn hoặc chạy vô hạn. Nondeterminism và shared global state khiến failure khó reproduce. Corpus regression lưu input đã làm lỗi để lần chạy sau kiểm tra lại, không chỉ giữ một log random seed.

## Khái niệm và mô hình làm việc

Fuzzer tìm inputs phá properties, không tự biết business correctness nếu oracle yếu.

## Cơ chế và những ranh giới cần giữ

Seed representative edges; assert round-trip, no panic, size bounds hoặc semantic invariant. Keep function deterministic và avoid unbounded external I/O.

## Áp dụng vào hệ thống thật

FuzzDecimalRoundTrip trong examples checks int64 parse/format including limits.

## Những đường lỗi cần hiểu

Oracle chỉ gọi code không assert; huge allocations; flaky time/network.

## Lần theo bằng chứng khi có sự cố

Save minimized failing corpus, turn critical failures into regression seeds.

## Đánh đổi và giới hạn sử dụng

Fuzz complement unit/integration, không chứng minh absence of bugs.

## Thực hành, debugging và kết luận

Repo có FuzzLowerBound và round-trip decimal lab. Chạy thời lượng hữu hạn, lưu case lỗi, sửa rồi kiểm tra lại cùng input. Fuzz tìm counterexample trong không gian đã khám phá; không là chứng minh mọi input an toàn hay thay threat modeling.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

FuzzLowerBound trong examples không chỉ so với một binary-search implementation khác: nó kiểm partition invariant trên mọi element trước/sau returned index. Điều này bắt off-by-one và duplicate-boundary errors. FuzzDecimalRoundTrip bao int64 extremes; minimized failing input được lưu thành seed. Với parser untrusted, thêm allocation/input bound để fuzz không thành uncontrolled memory workload.
