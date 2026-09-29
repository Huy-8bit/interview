# HTTP server configuration

## Bài toán và ví dụ đầu tiên

Dùng http.ListenAndServe với cấu hình mặc định tiện cho demo, nhưng service phải biết client được phép giữ socket và gửi body bao lâu. Server cấu hình tường minh giúp review các giới hạn đó cùng loại endpoint.

## Đi từng bước qua một tình huống

Một GET JSON nhỏ cần budget khác upload file và streaming. ReadHeaderTimeout giới hạn đọc headers, IdleTimeout giới hạn lúc chờ request tiếp theo, còn WriteTimeout không tự là context deadline cho mọi business work. Body size cần giới hạn riêng trước decode để một payload lớn không chiếm memory vô hạn.

## Hiểu cơ chế từ kết quả quan sát

Handler có thể chạy concurrent trên nhiều request nên shared state phải đồng bộ. Header phải được đặt trước khi response được commit qua WriteHeader/Write. ResponseWriter không được giữ để viết sau khi ServeHTTP return. Middleware recovery chỉ có phạm vi goroutine tương ứng và cần biết response đã gửi chưa.

## Khái niệm và mô hình làm việc

Explicit Server configuration làm resource budget review được.

## Cơ chế và những ranh giới cần giữ

Set ReadHeaderTimeout, body limits, IdleTimeout và endpoint-specific deadline; ReadTimeout bao đọc request, WriteTimeout có semantics theo connection/protocol cần test.

## Áp dụng vào hệ thống thật

API nhỏ có total request budget; streaming dùng policy riêng và ResponseController khi thích hợp.

## Những đường lỗi cần hiểu

Global WriteTimeout quá ngắn cắt stream; large body không limit gây memory pressure.

## Lần theo bằng chứng khi có sự cố

Test slowloris, delayed body, disconnect và partial response; xem LB timeout cùng server config.

## Đánh đổi và giới hạn sử dụng

Không có một bộ timeout tối ưu cho mọi endpoint.

## Thực hành, debugging và kết luận

Test malformed input, oversized body, client cancel và dependency chậm bằng httptest server thực khi cần network behavior. Quan sát active requests và write latency, không chỉ handler CPU. Chọn timeout từ workload, ghi rõ streaming policy và kết hợp shutdown thay vì kết thúc bằng os.Exit ở mọi lỗi.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)

## Thực hành có điều kiện kiểm chứng

Lab gồm ba clients: gửi header từng byte, gửi body lớn hơn giới hạn, và ngắt kết nối khi handler đang gọi downstream. Verify timeout/413/cancellation riêng; không kỳ vọng WriteTimeout tự return hàm CPU loop. Chạy cùng proxy timeout thật để thấy client-observed status có thể khác status handler đã cố ghi. Theo dõi FD và G sau khi clients dừng.
