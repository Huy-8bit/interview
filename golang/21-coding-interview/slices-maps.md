# Slices/maps coding: Two Sum

## Bài toán và ví dụ đầu tiên

Two Sum yêu cầu tìm hai index khác nhau có tổng target. Map có thể lưu các số đã đi qua để mỗi số mới chỉ cần tìm phần bù, giảm việc thử mọi cặp.

## Đi từng bước qua một tình huống

Với nums=[2,7,11], target9: ở2 chưa thấy7 nên lưu2→0; ở7 thấy2 trong map nên trả0,1. Lookup trước insert giữ việc không dùng cùng index hai lần. Với [3,3], target6, lần3 đầu lưu rồi lần3 sau mới tìm thấy cặp hợp lệ.

## Code và giải thích từng bước

```go
func TwoSum(nums []int, target int) (int, int, bool) {
	seen := make(map[int]int, len(nums))
	for i, n := range nums {
		if j, ok := seen[target-n]; ok {
			return j, i, true
		}
		seen[n] = i
	}
	return 0, 0, false
}
```

### Giải thích code từng bước

Map seen chỉ giữ phần tử ở index nhỏ hơn i vì lookup xảy ra trước insert. Nếu thấy target-n, j và i chắc chắn khác nhau. Nếu không thấy, lưu index để các vòng sau dùng; return false chỉ sau khi đã thử mọi phần tử. Make map có capacity hint nhưng không phải trần input.

## Hiểu cơ chế từ kết quả quan sát

Slice là input có index, map là chỉ mục giá trị→vị trí đã thấy. Average time O(n), memory O(n), phụ thuộc map lookup assumptions. Duplicate values cần semantics một cặp bất kỳ; nếu đề yêu cầu tất cả cặp hoặc count thì state và complexity khác.

## Khái niệm và mô hình làm việc

Hash lookup đổi brute force O(n²) thành expected O(n) time với O(n) memory.

## Cơ chế và những ranh giới cần giữ

TwoSum lưu index đã đi qua; lookup complement trước insert để không reuse cùng index. Duplicate values hợp lệ nếu indices khác. Integer subtraction cần domain không overflow.

## Áp dụng vào hệ thống thật

Dedup/joins in-memory trong batch bounded, không giữ map toàn stream vô hạn.

## Những đường lỗi cần hiểu

Insert trước lookup trả cùng index; map không init; memory grows với input không bound.

## Lần theo bằng chứng khi có sự cố

Test [3,3], target 6; no pair; empty; negative values và boundary numeric domain.

## Đánh đổi và giới hạn sử dụng

Sorted two-pointers O(1) extra space nếu input sorted; sort làm đổi original indices trừ giữ mapping.

## Thực hành, debugging và kết luận

Test no solution, duplicates và negative numbers; ghi giả định int arithmetic không overflow. Không mutate input nếu contract không cho phép. Khi giải production matching, cùng thuật toán cần xét streaming window, size bound và identity semantics thay vì chỉ copy solution interview.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
