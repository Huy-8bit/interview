# Two pointers trên sorted data

## Bài toán và ví dụ đầu tiên

Tìm hai số có tổng target trong slice đã sort mà không dùng map. Hai pointers ở hai đầu tận dụng thứ tự: biết tổng quá nhỏ hay quá lớn cho phép bỏ một vùng ứng viên có chứng minh.

## Đi từng bước qua một tình huống

Với [1,2,4,7], target 6: 1+7=8 quá lớn nên giảm right; 1+4=5 quá nhỏ nên tăng left; 2+4=6 trả hai index. Khi sum nhỏ, giữ left cũ và giảm right chỉ làm tổng nhỏ hơn nữa, nên bỏ left là hợp lý. Lập luận tương tự cho sum lớn.

## Code và giải thích từng bước

```go
func TwoSumSorted(nums []int, target int) (int, int, bool) {
	left, right := 0, len(nums)-1
	for left < right {
		sum := nums[left] + nums[right]
		if sum == target {
			return left, right, true
		}
		if sum < target {
			left++
		} else {
			right--
		}
	}
	return 0, 0, false
}
```

### Giải thích code từng bước

Hai biên chỉ đi vào trong. Hàm trả ngay khi tổng bằng target, còn nhánh nhỏ/lớn loại một đầu theo tính đơn điệu của input sorted. false báo không có cặp index khác nhau. Arithmetic int được giả định không overflow trong contract lab.

## Hiểu cơ chế từ kết quả quan sát

Loop left<right bảo đảm dùng hai phần tử khác nhau. Thời gian O(n), extra memory O(1) sau khi input đã sort. Nếu cần trả original indices và phải sort đầu vào, cần giữ mapping hoặc dùng TwoSum map; sorting còn có chi phí và mutation/ownership.

## Khái niệm và mô hình làm việc

Sorted order cho phép loại một đầu sau mỗi comparison, đạt O(n) time/O(1) extra space.

## Cơ chế và những ranh giới cần giữ

Nếu sum<target tăng left vì mọi pair với current left và right nhỏ hơn nữa không đủ; sum>target giảm right. Distinct indices left<right.

## Áp dụng vào hệ thống thật

Merge/intersection/dedup sorted batches; arithmetic cần no-overflow domain hoặc checked operations.

## Những đường lỗi cần hiểu

Dùng trên unsorted input; mutation/sort làm mất original index; overflow sum đảo comparison.

## Lần theo bằng chứng khi có sự cố

Test duplicates, no result, minimal length và extreme values theo contract.

## Đánh đổi và giới hạn sử dụng

Hash map giữ original indices khi unsorted, tốn memory; sort rồi pointers thêm O(n log n).

## Thực hành, debugging và kết luận

Test empty, one item, duplicates, negatives và no solution. Lab giả định arithmetic không overflow; domain rộng cần kiểm tra hoặc kiểu số phù hợp. Đừng áp two pointers cho predicate không đơn điệu hoặc input chưa sorted chỉ vì bài có hai index.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
