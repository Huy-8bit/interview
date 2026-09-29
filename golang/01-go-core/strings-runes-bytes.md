# Strings, runes và bytes

## Bài toán và ví dụ đầu tiên

API giới hạn tên người dùng 20 ký tự nhưng len(name) báo lớn hơn số ký tự nhìn thấy. String trong Go là chuỗi byte; UTF-8 có thể dùng nhiều byte cho một Unicode code point. Một ký tự hiển thị còn có thể gồm nhiều code point.

## Đi từng bước qua một tình huống

Với chữ Việt có dấu, byte count, rune count và số ký tự người dùng nhìn có thể khác nhau. Range trên string trả byte index và rune đã decode; index không phải thứ tự rune 0,1,2. Cắt s[:n] theo byte có thể cắt giữa một encoding và tạo chuỗi không hợp lệ cho UI.

## Hiểu cơ chế từ kết quả quan sát

Rune là alias của int32 dùng biểu diễn code point; grapheme cluster là đơn vị gần ký tự người dùng thấy, có thể gồm base letter và combining mark hoặc nhiều rune emoji. []rune hữu ích khi thuật toán theo code point nhưng không giải quyết mọi xử lý ngôn ngữ. String bất biến qua API Go thông thường; []byte mutable có ownership khác.

## Khái niệm và mô hình làm việc

String là chuỗi byte immutable; UTF-8 phổ biến nhưng string có thể chứa byte không hợp lệ. Rune là Unicode code point, không phải grapheme.

## Cơ chế và những ranh giới cần giữ

len(string) đếm byte; range decode rune và trả byte index; []rune đổi sang code points. Combining marks và emoji có thể cần nhiều rune cho một ký tự người dùng nhìn thấy.

## Áp dụng vào hệ thống thật

Giới hạn upload bằng byte; giới hạn hiển thị dùng quy tắc Unicode phù hợp. Dùng strings.Builder cho xây chuỗi theo batch khi benchmark ủng hộ.

## Những đường lỗi cần hiểu

Cắt s[:n] giữa UTF-8 sequence; thuật toán sliding window dùng byte nhưng đề yêu cầu Unicode; log secret khi debug encoding.

## Lần theo bằng chứng khi có sự cố

Reproduce với tiếng Việt, combining marks và invalid UTF-8; xem allocation do conversions lặp lại.

## Đánh đổi và giới hạn sử dụng

[]byte hợp protocol, rune hợp code points; grapheme segmentation cần thư viện phù hợp và version Unicode rõ.

## Thực hành, debugging và kết luận

Giới hạn upload/network bằng byte vì đó là tài nguyên thật. Với UI, chọn quy tắc Unicode theo sản phẩm và test combining marks, emoji, invalid UTF-8. Khi tối ưu string concatenation, benchmark strings.Builder với workload thật và đừng log nội dung nhạy cảm chỉ để debug encoding.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](interfaces.md)
- [Error handling và error chains](errors.md)
- [unit-testing](../18-testing/unit-testing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/ref/spec)
