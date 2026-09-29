# Tự đánh giá bằng một walkthrough hoàn chỉnh

Tên file được giữ cho link cũ. Trang này giúp kiểm tra khả năng giải thích sau khi học, không là ngân hàng câu hỏi hoặc danh sách thuật ngữ cần thuộc.

## Từ một request tới tài nguyên được trả

Chọn endpoint đọc dữ liệu và gọi partner. Theo request từ HTTP handler qua context, SQL pool, query/Rows và HTTP response body. Ghi ai tạo/acquire, ai dùng, ai Close/cancel và owner nào chờ worker kết thúc. Đặt client disconnect ở giữa flow rồi chỉ rõ operation nào quan sát, operation nào có thể đã commit và state nào cần đối soát.

Nếu chỉ viết “dùng context” mà không chỉ ra điểm select hoặc Context API, lifetime chưa được chứng minh. Nếu chỉ viết “dùng WaitGroup” mà worker không có đường thoát, shutdown vẫn có thể treo. Đọc lại [cancellation](../05-context/cancellation.md) và [pool](../04-concurrency/worker-pool.md) để nối hai phần.

## Từ code tới runtime và bằng chứng

Chạy một ví dụ [slice](../01-go-core/arrays-slices.md) với cap khác nhau, rồi giải thích aliasing và allocation có điều kiện. Chạy [labs](../examples/README.md) với race detector và đọc một CPU/heap profile đúng sample type. Phân biệt điều test đã kiểm chứng với điều mới là assumption; compile SQL không chứng minh isolation của PostgreSQL.

## Từ phiên bản đơn giản tới thiết kế lớn hơn

Lấy một [system design](../13-system-design/README.md), trình bày V1 chỉ với các thành phần cần thiết. Dùng workload và failure story để biện minh replica/cache/queue tiếp theo. Theo crash trước/sau durable commit rồi xác định retry identity, checkpoint và recovery owner. Một sơ đồ rõ phải giải thích được mũi tên nào đồng bộ, mũi tên nào bất đồng bộ và lúc nào client nhận accepted/completed.

## Cách dùng kết quả tự đánh giá

Ghi một chỗ còn thiếu bằng câu cụ thể, ví dụ “chưa phân biệt pool wait với query execute” rồi đọc/chạy bài liên quan. Tránh tự chấm đã biết chỉ vì nhận ra tên thuật ngữ. Khi nền tảng đã vững, [mock interview](../23-mock-interview/README.md) giúp luyện trình bày có thời gian, còn [cheatsheets](../24-cheatsheets/README.md) giúp tìm lại điều kiện và links.
