# Binary search bằng half-open interval

## Bài toán và ví dụ đầu tiên

Cần tìm vị trí đầu tiên có giá trị ít nhất bằng target trong một slice đã sort. Duyệt tuyến tính đúng nhưng tốn O(n); binary search loại một nửa vùng ứng viên mỗi bước khi predicate có tính đơn điệu.

## Đi từng bước qua một tình huống

Với [1,3,3,7] và target3, left=0,right=4. Mid2 có value3 nên right=2; mid1 vẫn3 nên right=1; mid0 có1 nên left=1. Hai biên gặp ở1 là vị trí đầu tiên phù hợp. Target8 đưa kết quả tới len=4, biểu diễn không có phần tử đáp ứng, không phải index được phép đọc.

## Code và giải thích từng bước

```go
func LowerBound(sorted []int, target int) int {
	left, right := 0, len(sorted)
	for left < right {
		mid := left + (right-left)/2
		if sorted[mid] < target {
			left = mid + 1
		} else {
			right = mid
		}
	}
	return left
}
```

### Giải thích code từng bước

left/right bắt đầu bao toàn input. Nhánh sorted[mid]<target loại mid và mọi index trước nó khỏi boundary ứng viên; nhánh còn lại giữ mid làm biên phải. Khi hai biên bằng nhau, return là boundary đầu tiên, kể cả len khi không có phần tử phù hợp. Hàm không allocate hay block và yêu cầu input đã sort.

## Hiểu cơ chế từ kết quả quan sát

Invariant là các index trước left đã biết nhỏ hơn target, các index từ right trở đi đã biết không nhỏ hơn target; boundary đáp án nằm giữa hai biên. Mỗi update phải thu hẹp vùng để loop kết thúc. Mid=left+(right-left)/2 tránh cộng hai biên lớn không cần thiết.

## Khái niệm và mô hình làm việc

LowerBound tìm first index có value≥target trong sorted input; kết quả có thể len nếu không có.

## Cơ chế và những ranh giới cần giữ

Maintain [left,right) candidates, mid=left+(right-left)/2; nums[mid]<target thì left=mid+1, ngược lại right=mid. O(log n), O(1).

## Áp dụng vào hệ thống thật

Cursor/index lookup theo monotonic predicate; database index vẫn có I/O costs khác.

## Những đường lỗi cần hiểu

Off-by-one, infinite loop không shrink, overflow midpoint, input không sorted.

## Lần theo bằng chứng khi có sự cố

Fuzz partition property: mọi j<i nhỏ hơn target, mọi j≥i không nhỏ hơn.

## Đánh đổi và giới hạn sử dụng

Linear scan tốt cho very small data; predicate phải monotonic.

## Thực hành, debugging và kết luận

Implementation LowerBound và property test trong examples kiểm tra cả partition trước/sau kết quả, không chỉ vài đáp án. Test empty, all equal và target ngoài range. Input không sorted vi phạm precondition; binary search không tự kiểm tra/sort hộ. Trong production, index DB còn có I/O và concurrency semantics ngoài phép so sánh này.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
