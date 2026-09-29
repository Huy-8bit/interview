# Sliding window: unique bytes

## Bài toán và ví dụ đầu tiên

Tìm đoạn liên tiếp dài nhất không lặp byte trong chuỗi. Nếu thử mọi substring rồi kiểm tra trùng, work lặp lại nhiều. Sliding window giữ một vùng hợp lệ và điều chỉnh biên khi thêm phần tử mới.

## Đi từng bước qua một tình huống

Với abba, right0 nhận a, window a; right1 nhận b, window ab, best2. Right2 gặp b đã ở vị trí1 nên left lên2, window b. Right3 gặp a cũ ở0 nằm ngoài window, left không được lùi lại; window ba có length2. Điều kiện chỉ tăng left giữ invariant.

## Code và giải thích từng bước

```go
func LongestUniqueBytes(s string) int {
	var last [256]int
	left, best := 0, 0
	for right := 0; right < len(s); right++ {
		b := s[right]
		if last[b] > left {
			left = last[b]
		}
		if right-left+1 > best {
			best = right - left + 1
		}
		last[b] = right + 1
	}
	return best
}
```

### Giải thích code từng bước

last là array256 zero value, dùng index byte để tìm biên sau lần gặp trước. Chỉ tăng left nếu vị trí cũ nằm trong window; cập nhật best trước khi lưu right+1. Hàm đi theo byte indexes và không decode Unicode, không mutate input và không có concurrency bên trong.

## Hiểu cơ chế từ kết quả quan sát

Lab lưu last[b]=right+1 để zero value biểu diễn chưa thấy và giá trị đã lưu là biên tối thiểu mới. Mỗi right đi qua chuỗi một lần, left chỉ tăng nên thời gian O(n), state256 vị trí cho byte. Thuật toán đếm bytes, không rune/grapheme; tên hàm ghi rõ contract đó.

## Khái niệm và mô hình làm việc

Window [left,right] giữ invariant không lặp; last-seen index cho phép nhảy left thay scan lại.

## Cơ chế và những ranh giới cần giữ

Store last index+1, update left=max(left,last[b]); count right-left+1. O(n) time,256 slots cho bytes. Unicode rune/grapheme là contract khác.

## Áp dụng vào hệ thống thật

Byte protocol tokens hoặc ASCII interview problem; user-visible text cần chọn Unicode semantics.

## Những đường lỗi cần hiểu

Input abba làm left lùi nếu không max; rune dùng byte indexing sai.

## Lần theo bằng chứng khi có sự cố

Test empty, repeated, abba và non-ASCII để nêu giới hạn byte algorithm.

## Đánh đổi và giới hạn sử dụng

Window chỉ hợp khi invariant cập nhật incremental; không áp mù cho non-monotonic constraints.

## Thực hành, debugging và kết luận

Test empty, all same, abba và chuỗi byte không UTF-8. Nếu product cần ký tự hiển thị, đổi đơn vị và mapping indexes trước khi reuse. Lỗi phổ biến là đặt left bằng last vô điều kiện khiến left lùi, hoặc dùng byte thuật toán cho Unicode rồi trả kết quả không đúng yêu cầu.


## Đọc tiếp

- [README](../examples/README.md)
- [Coding interview workflow](go-coding-patterns.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)

## Runnable solution

[Algorithms implementation](../examples/algorithms.go) và [edge-case/property tests](../examples/algorithms_test.go)

Chạy từ `golang/examples`: `go test -race ./...`. Đọc contract ở function comment; không mở rộng numeric/Unicode/cycle assumptions mà không đổi validation và tests.
