# Giáo trình Go backend: từ ví dụ nhỏ tới hệ thống production

Tài liệu tiếng Việt dành cho backend engineer mới tìm hiểu Go sâu. Mỗi bài đi từ bài toán và ví dụ quan sát được tới cơ chế, runtime khi cần, failure/debugging và trade-off. Đọc code cùng phần giải thích ngay sau nó; mọi Mermaid diagram có mục **Cách đọc diagram** mô tả nodes, arrows và ý nghĩa luồng.

## Bắt đầu học

Bắt đầu [giá trị và slices](01-go-core/arrays-slices.md), [goroutine](03-goroutines-scheduler/goroutine.md) và [context](05-context/context-basics.md) theo kiến thức đang thiếu. Sau đó nối thành đường request qua [HTTP](06-http-backend/net-http.md) và [database](08-database/database-sql.md). [Lộ trình 30 ngày](00-roadmap/30-day-plan.md) dành thời gian cho ví dụ và lab; [14 ngày](00-roadmap/14-day-crash-plan.md) là lịch tập trung vào nền tảng, cần điều chỉnh khi một cơ chế chưa rõ.

Một cách học hiệu quả là dự đoán output, chạy ví dụ, giải thích khác biệt rồi đổi một điều kiện: capacity của slice/channel, thời điểm cancel, pool size hoặc điểm crash. Với hệ thống phân tán, theo durable state sau từng bước thay vì chỉ nhìn response của caller. Các [mức ưu tiên](00-roadmap/priority-topics.md) giúp chọn thứ tự, không là danh sách phải học thuộc.

## Bản đồ giáo trình

| Phần | Nội dung |
|---|---|
| [00-roadmap](00-roadmap/README.md) | Cách học giáo trình Go backend |
| [01-go-core](01-go-core/README.md) | Giá trị, kiểu dữ liệu và ownership trong Go |
| [02-memory-runtime](02-memory-runtime/README.md) | Bộ nhớ và runtime từ lifetime của object |
| [03-goroutines-scheduler](03-goroutines-scheduler/README.md) | Từ goroutine tới cách runtime chia CPU |
| [04-concurrency](04-concurrency/README.md) | Đồng bộ dữ liệu và vòng đời công việc |
| [05-context](05-context/README.md) | Context từ request bị bỏ dở tới cleanup |
| [06-http-backend](06-http-backend/README.md) | HTTP từ kết nối đến response và shutdown |
| [07-api-design](07-api-design/README.md) | Contract giữa backend và client |
| [08-database](08-database/README.md) | SQL từ pool connection tới invariant durable |
| [09-redis-cache](09-redis-cache/README.md) | Cache, freshness và tải khi cache lỗi |
| [10-messaging](10-messaging/README.md) | Message từ publish tới effect và replay |
| [11-software-architecture](11-software-architecture/README.md) | Tổ chức code theo trách nhiệm và dependency |
| [12-distributed-systems](12-distributed-systems/README.md) | Suy luận khi chỉ một phần hệ thống thất bại |
| [13-system-design](13-system-design/README.md) | Xây hệ thống qua từng phiên bản có lý do |
| [14-microservices](14-microservices/README.md) | Vận hành các boundary qua mạng |
| [15-docker-kubernetes](15-docker-kubernetes/README.md) | Nối Go lifecycle với container và deployment |
| [16-performance](16-performance/README.md) | Đo trước khi tối ưu |
| [17-observability](17-observability/README.md) | Từ tín hiệu tới lời giải thích sự cố |
| [18-testing](18-testing/README.md) | Kiểm chứng hành vi tại đúng boundary |
| [19-security](19-security/README.md) | Giữ trust boundary trong backend |
| [20-production-scenarios](20-production-scenarios/README.md) | Điều tra sự cố bằng timeline và giả thuyết |
| [21-coding-interview](21-coding-interview/README.md) | Học thuật toán qua invariant và walkthrough |
| [22-behavioral](22-behavioral/README.md) | Diễn đạt quyết định và đóng góp kỹ thuật |
| [23-mock-interview](23-mock-interview/README.md) | Phụ lục luyện phỏng vấn sau khi học lý thuyết |
| [24-cheatsheets](24-cheatsheets/README.md) | Phụ lục tra cứu sau khi đã hiểu bài |

## Thực hành và giới hạn của ví dụ

[Go labs](examples/README.md) có worker pool, HTTP client/server, SQL cleanup patterns và thuật toán cùng tests. Code module dùng language baseline Go 1.23, được kiểm tra bằng toolchain cục bộ Go 1.26.4; đây không phải tuyên bố phiên bản mới nhất. Runtime internals được phân biệt với language/package contract và có [nguồn chính thức](references.md) để đối chiếu theo version.

[Chín bài system design](13-system-design/README.md) xây từ phiên bản đơn giản, giải thích lúc nào thêm replica, cache hoặc queue và cách phục hồi sau failure. Các mục tiêu20k RPS hoặc 4–5 tỷ records là assumptions để tính toán; repository không tuyên bố đã benchmark workload đó. [Mười hai case production](20-production-scenarios/README.md) là timeline mô phỏng, không là sự cố thật đã xảy ra ở workspace.

Câu hỏi phỏng vấn chỉ ở [phụ lục luyện tập](23-mock-interview/README.md). [Cheatsheets](24-cheatsheets/README.md) dùng để tra lại sau khi đã học bài, không thay giáo trình. [Báo cáo kiểm tra](00-roadmap/repository-audit.md) phân biệt structural checks, compile examples, behavior tests và những integration chưa chạy.
