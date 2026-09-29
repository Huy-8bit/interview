# httptest: recorder versus server

## Bài toán và ví dụ đầu tiên

Handler có thể được gọi trực tiếp trong test để kiểm tra status/body mà không mở cổng thật. httptest cung cấp request/recorder và test server, hai công cụ phục vụ hai mức behavior khác nhau.

## Đi từng bước qua một tình huống

ResponseRecorder hữu ích cho handler parsing/response logic. NewServer/NewTLSServer tạo transport thật để test Client, cancellation và connection reuse. Test reuse cần đọc/Close body đúng và có thể dùng httptrace quan sát GotConn.Reused; Recorder không có TCP connection để chứng minh điều đó.

## Hiểu cơ chế từ kết quả quan sát

Test server handlers vẫn có thể chạy concurrent nên shared state test cần đồng bộ. Cleanup server/client body theo owner để test không leak. Delay behavior nên điều phối bằng channel và context, tránh Sleep đoán thời điểm request đã tới.

## Khái niệm và mô hình làm việc

ResponseRecorder test handler behavior in-process; httptest.Server tạo real HTTP stack cho client/protocol tests.

## Cơ chế và những ranh giới cần giữ

Recorder không mô phỏng TCP reuse/TLS/HTTP2; server + client + httptrace kiểm connection behavior. Close server/client idle conns sau test.

## Áp dụng vào hệ thống thật

Examples test body limits, canceled request và HTTP/1 reuse bằng GotConn.Reused.

## Những đường lỗi cần hiểu

Assert pooling với recorder không có socket; forget response body close làm server.Close chờ.

## Lần theo bằng chứng khi có sự cố

Run -race và cancellation scenarios; server errors phải report có owner.

## Đánh đổi và giới hạn sử dụng

Unit handler tests rẻ hơn real server; chọn theo câu hỏi cần xác minh.

## Thực hành, debugging và kết luận

Repo có http_test.go minh họa reuse, size bound và cancellation qua server thật. Nếu sandbox chặn loopback thì đó là hạn chế môi trường test, không tự là lỗi implementation. Ghi rõ checks nào cần network local khi chạy CI/tooling.


## Đọc tiếp

- [README](../examples/README.md)
- [Race condition versus data race](../04-concurrency/race-condition.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/testing)

## Thực hành có điều kiện kiểm chứng

TestFetchReusesConnection dùng real server và GotConn.Reused ở request thứ hai sau đọc body đầy đủ. Nếu đổi sang Recorder, test không có TCP/Transport pool nên không còn kiểm yêu cầu này. Test oversized body phải trả error mà vẫn Close; test canceled ctx dùng errors.Is để không phụ thuộc wrapped message text. Local socket permission là requirement môi trường, không bug business logic.
