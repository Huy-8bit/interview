# Kafka với Go: commit boundary

## Bài toán và ví dụ đầu tiên

Order service cần thông báo cho analytics và notification mà không chờ hai bên hoàn tất trước khi trả response. Một log sự kiện cho phép producer ghi một lần và các consumer đọc theo tiến độ riêng. Kafka tổ chức log thành topics và partitions, hỗ trợ replay trong phạm vi retention; nó không tự bảo đảm mọi side effect bên ngoài chỉ xảy ra một lần.

## Đi từng bước qua một tình huống

Topic orders có ba partitions. Producer chọn partition theo key/order routing; mỗi record trong một partition có offset biểu diễn vị trí trong log đó. Offset không là ID nghiệp vụ toàn hệ thống và không so thứ tự toàn topic giữa hai partitions. Consumer group analytics và group notifications có tiến trình độc lập, nên analytics chậm không trực tiếp kéo offset notifications lùi.

Trong một consumer group thông thường, partitions được phân cho members theo protocol của group. Với ba partitions, thêm consumer thứ tư không tự cho bốn consumer cùng xử lý bốn phần độc lập của log đó. Một hot key tập trung vào một partition vẫn có thể là bottleneck dù những partitions khác rảnh.

## Hiểu cơ chế từ kết quả quan sát

Consumer poll records, xử lý, rồi commit progress theo chính sách. Commit offset trước effect có thể làm mất effect khi crash giữa hai bước; effect trước commit có thể làm replay duplicate sau crash. Với DB side effect, lưu dedup ID và effect cùng transaction, rồi cho phép replay an toàn. Kafka transaction có phạm vi guarantees cụ thể; nó không biến một email hoặc charge qua API ngoài thành exactly-once.

Rebalance là thay đổi phân công partition khi membership/điều kiện group đổi. Worker đang xử lý phải phối hợp ownership mới, không tiếp tục commit progress vượt phần đã hoàn tất. Nếu xử lý concurrent offsets 10,11,12 mà 10 còn lỗi trong khi 12 xong, không được checkpoint qua gap như thể cả đoạn đã xong. Cần theo dõi contiguous completed frontier — biên hoàn tất liên tục — theo partition.

Batching tăng throughput bằng cách chia overhead trên nhiều record nhưng thêm thời gian chờ gom batch và memory. Retention là thời gian/dung lượng log được giữ theo policy, không phải “message đã được mọi consumer xử lý thì mới xóa”. Consumer lag phải được xử lý trước khi dữ liệu cần replay nằm ngoài retention, hoặc có nguồn rebuild khác.

## Khái niệm và mô hình làm việc

Kafka giữ append-only logs theo partition; producer publish records, consumer group chia partitions và theo dõi offsets.

## Cơ chế và những ranh giới cần giữ

Key quyết định partition/order scope. Consumer xử lý DB commit rồi commit offset có crash window tạo redelivery. Commit trước DB có nguy cơ mất effect. Go client cần versioned API, bounded polling/processing và shutdown.

## Áp dụng vào hệ thống thật

DB effect và processed_event unique record cùng transaction; sau commit mới advance contiguous offset.

## Những đường lỗi cần hiểu

Crash sau DB commit trước offset commit: message được đọc lại, idempotent transaction phải no-op an toàn.

## Lần theo bằng chứng khi có sự cố

Lag theo partition, oldest event age, processing rate/errors/rebalances; correlate DB latency.

## Đánh đổi và giới hạn sử dụng

At-least-once dễ implement nhưng cần dedup; Kafka transaction không tự bao external DB.

## Thực hành, debugging và kết luận

Giả sử input 10000 record/s, consumers chỉ hoàn tất 7000/s: backlog tăng 3000 record/s. Thêm consumer chỉ giúp khi còn partition parallelism và downstream còn capacity. Nếu DB đã bão hòa, thêm consumer làm query chậm hơn và tăng retries. Đo lag per partition, tuổi record cũ nhất, processing latency, rebalance rate và commit errors.

Bắt đầu hệ thống nhỏ bằng API+DB và một worker/durable jobs nếu đủ yêu cầu. Thêm Kafka khi cần log có nhiều group độc lập, replay, partitioning và throughput phù hợp, đồng thời chấp nhận vận hành broker, schema, lag và replay. Outbox giúp nối DB commit với publish; broker khỏe không sửa được dual-write gap trong producer.

Go client cụ thể có contract poll, goroutine safety, rebalance callback và shutdown riêng. Đọc version đã pin rồi thiết kế owner poll loop, bounded workers và checkpoint coordinator. Test crash sau DB commit trước offset commit, rebalance khi còn in-flight và poison record. Thành công của test là invariant giữ sau replay, không chỉ consumer kết nối được.



## Theo một record qua restart và checkpoint

Giả sử partition P có offsets 100,101,102. Consumer đọc cả ba rồi giao ba workers. Offset102 hoàn tất trước,100 tiếp theo,101 đang chờ DB. Nếu commit progress vượt102 lúc này, crash rồi restart có thể bỏ qua101 theo semantics vị trí đã commit. Coordinator cần biết đoạn liên tục nào đã hoàn tất: sau 100 chỉ có thể tiến qua 100; khi101 xong mới gộp tới102. Giá trị offset API ghi thường biểu diễn vị trí đọc tiếp theo, nên kiểm tra convention client thay vì nhầm “last processed” và “next to read”.

Nếu101 lỗi transient, giữ ordering/budget theo partition hoặc key tùy contract. Đưa101 vào retry topic rồi tiến checkpoint có thể phù hợp event độc lập, nhưng làm102 effect xảy ra trước101; đó là thay đổi semantics phải được chấp nhận. Một payment state machine có version checks khác một analytics counter có thể cộng giao hoán. Broker không biết các quan hệ nghiệp vụ này để tự chọn đúng.

Khi rebalance, assignment của P chuyển sang consumer khác. Worker cũ có thể vẫn hoàn thành DB call sau khi đã mất ownership. Dedup/version guard bảo vệ effect, còn checkpoint logic phải tuân generation/protocol của client để stale progress không phá ownership mới. Hủy context của worker chỉ yêu cầu dừng, không rollback DB đã commit.

Thực hành bằng state table có offset, started, effect_committed, progress_committed và assignment epoch. Chèn crash sau mỗi cột để xác định record nào replay và invariant nào giữ. Sau đó mới viết test với client/DB thật hoặc test coordinator logic độc lập. Metrics lag đẹp hơn không là thành công nếu checkpoint đã nhảy qua gap; verification cần kiểm tra durable effect và contiguous progress.

## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)
