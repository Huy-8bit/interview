# PART 2 — WHY REDIS IS FAST

> **Trước:** [01 — Redis Architecture](01-redis-architecture.md) · **Tiếp:** [03 — Event Loop](03-event-loop.md)
> **Độ ưu tiên:** Rất cao. "Why is Redis fast?" là câu hỏi phỏng vấn số một về Redis — và câu trả lời "vì nó in-memory và single-threaded" là câu trả lời **chưa đạt**. Chương này phân rã tốc độ Redis thành từng thành phần đo được, và chỉ ra chính xác khi nào mỗi thành phần sụp đổ.

---

## Mục lục

1. [Simple mental model: ngân sách thời gian của một request](#1-simple-mental-model)
2. [WHAT — "Nhanh" nghĩa là gì: latency, throughput, tail latency](#2-what--nhanh-nghĩa-là-gì)
3. [Nguyên nhân 1 — Memory access](#3-nguyên-nhân-1--memory-access)
4. [Nguyên nhân 2 — Efficient data structures](#4-nguyên-nhân-2--efficient-data-structures)
5. [Nguyên nhân 3 — Single command-execution thread](#5-nguyên-nhân-3--single-command-execution-thread)
6. [Nguyên nhân 4 — Event-driven architecture & non-blocking I/O](#6-nguyên-nhân-4--event-driven--non-blocking-io)
7. [Nguyên nhân 5 — Minimal protocol overhead: RESP](#7-nguyên-nhân-5--minimal-protocol-overhead-resp)
8. [Nguyên nhân 6 — Efficient algorithms và amortization](#8-nguyên-nhân-6--efficient-algorithms-và-amortization)
9. [Nguyên nhân 7 — Pipelining & batching](#9-nguyên-nhân-7--pipelining--batching)
10. [Nguyên nhân 8 — Những thứ Redis KHÔNG làm](#10-nguyên-nhân-8--những-thứ-redis-không-làm)
11. [DATA FLOW — Phân rã 200 µs của một GET](#11-data-flow--phân-rã-200-µs-của-một-get)
12. [Redis 100k ops/s thực chất phụ thuộc vào gì](#12-redis-100k-opss-thực-chất-phụ-thuộc-vào-gì)
13. [WHAT HAPPENS IF — Các trường hợp Redis chậm](#13-what-happens-if--các-trường-hợp-redis-chậm)
14. [PRODUCTION BEHAVIOR](#14-production-behavior)
15. [TRADE-OFF](#15-trade-off)
16. [COMMON MISUNDERSTANDINGS](#16-common-misunderstandings)
17. [INTERVIEW QUESTIONS](#17-interview-questions)
18. [KEY TAKEAWAYS](#18-key-takeaways)

---

## 1. Simple mental model

Một request Redis giống **gửi thư qua bưu điện tới một người tính nhẩm siêu tốc**:

- Thư đi mất **200 µs** (network RTT trong datacenter).
- Bưu cục nhận và bóc phong bì mất **vài µs** (syscall, parse).
- Người tính nhẩm trả lời mất **0.1–2 µs** (execute lệnh O(1) trên RAM).
- Thư trả lời lại đi **một chiều** về.

Nếu bạn muốn "Redis nhanh hơn", tối ưu người tính nhẩm gần như vô ích — **phần lớn thời gian nằm ở bưu điện**. Vì vậy các kỹ thuật tăng tốc Redis thật sự là: gửi nhiều câu hỏi trong một lá thư (pipelining), hỏi một câu gộp (MGET, Lua), hoặc đặt người tính nhẩm gần hơn (local cache).

Nhưng: nếu một ai đó gửi bài toán "tính tổng 10 triệu số", người tính nhẩm mất 2 giây và **mọi lá thư khác phải xếp hàng**.

---

## 2. WHAT — "Nhanh" nghĩa là gì

Ba đại lượng khác nhau, thường bị nhầm:

| Đại lượng | Định nghĩa | Redis điển hình | Chi phối bởi |
|---|---|---|---|
| **Service time** | Thời gian main thread thực thi một lệnh | 0.1–5 µs cho lệnh O(1) nhỏ | Data structure, complexity, kích thước value, CPU cache |
| **Latency (client-side)** | Từ lúc client gửi đến lúc nhận reply | 100–500 µs trong DC | Network RTT, syscall, hàng đợi, client library |
| **Throughput** | Số lệnh/giây server xử lý | 100k–200k (không pipeline), 1M+ (pipeline/IO threads) | Chi phí per-request cố định, CPU main thread, NIC |
| **Tail latency** | p99, p99.9 | Có thể 10–1000x median khi có sự cố | Lệnh chậm, fork, fsync, eviction, GC phía client |

Với hệ thống một thread, **latency = thời gian chờ + service time**. Theo lý thuyết hàng đợi (M/M/1), khi utilization ρ của main thread tiến tới 1, thời gian chờ trung bình tăng như ρ/(1−ρ): ở 50% utilization, chờ ≈ 1× service time; ở 90%, chờ ≈ 9×; ở 99%, ≈ 99×. Đây là lý do Redis "đang nhanh" có thể đột ngột "rất chậm" khi tải tăng thêm 10%.

---

## 3. Nguyên nhân 1 — Memory access

### 3.1 WHAT

Toàn bộ dataset nằm trong RAM của process. Đọc một value = vài lần truy cập pointer trong RAM, không có I/O.

### 3.2 WHY — RAM nhanh hơn disk ở đâu

Các con số bậc độ lớn (thay đổi theo phần cứng, dùng để suy luận, không phải cam kết):

| Thao tác | Latency xấp xỉ |
|---|---|
| L1 cache hit | ~1 ns |
| L2 cache hit | ~4 ns |
| L3 cache hit | ~10–40 ns |
| **Main memory (DRAM)** | **~80–120 ns** |
| NVMe SSD random read 4 KB | ~10–100 µs |
| SATA SSD random read | ~100 µs |
| HDD seek | ~5–10 ms |
| Network RTT cùng datacenter | ~100–500 µs |
| Network RTT cross-region | ~10–100 ms |

Khác biệt không chỉ ở con số:
1. **Granularity**: RAM truy cập theo **cache line 64 byte**; disk theo **block/page 4 KB+**. Đọc 1 field 20 byte từ disk vẫn phải đọc cả page.
2. **Không qua kernel**: đọc RAM của chính process là một lệnh CPU `mov`. Đọc disk phải qua syscall, VFS, page cache, block layer, driver, thiết bị.
3. **Không có "cache miss" cấp database**: PostgreSQL có buffer pool — miss thì đọc disk, latency nhảy từ µs lên ms. Redis không có tầng này: **mọi truy cập đều là "hit"**, nên latency đồng đều.
4. **Random access rẻ**: cấu trúc dựa trên pointer (hash table chaining, skip list, linked list) chỉ khả thi hiệu quả trong RAM. Trên disk, mỗi lần theo pointer = một lần I/O ngẫu nhiên — đó là lý do database disk dùng B-tree (fan-out lớn, ít tầng).

### 3.3 Redis có bao giờ dùng disk không?

Có, nhưng **không trên đường phục vụ lệnh**:

| Khi nào | Ai làm | Ảnh hưởng đến lệnh client |
|---|---|---|
| AOF `write()` | Main thread, trong `beforeSleep` | Có, nhưng nhỏ (ghi vào page cache); lớn nếu disk bị nghẽn khi đang fsync |
| AOF `fsync()` everysec | BIO thread | Gián tiếp (có thể chặn write() tiếp theo) |
| AOF `fsync()` always | Main thread | **Trực tiếp**: mỗi lượt event loop chờ fsync |
| RDB snapshot | Fork child | Gián tiếp: fork latency + COW |
| Full sync replication (disk-based) | Fork child ghi file, main thread gửi file | Gián tiếp |
| Startup load | Main thread | Server ở trạng thái LOADING |
| **Swap** (không mong muốn) | Kernel | **Thảm họa**: một page fault chạm swap = ms |

### 3.4 PERFORMANCE IMPACT — Memory cũng có giới hạn

"In-memory" không có nghĩa "mọi truy cập đều 1 ns". Một GET trên dict lớn:
- Hash key (SipHash) → index bucket → **cache miss** (bucket array lớn không nằm trong CPU cache) → đọc `dictEntry` → **cache miss** → so sánh key (đọc sds key) → **cache miss** → đọc `robj` value → **cache miss** → đọc dữ liệu value.

Mỗi lần theo pointer có thể là ~100 ns. Một GET có thể tốn **4–5 cache miss ≈ 0.5 µs** chỉ riêng truy cập memory. Đây là lý do các bản mới (Redis 8.x, Valkey 8.x) tối ưu mạnh việc **embed key vào object**, **prefetch** memory cho nhiều lệnh trong pipeline (Redis 8.4 thêm cơ chế lookahead prefetch), và thay cấu trúc hash table cho cache-friendly hơn.

---

## 4. Nguyên nhân 2 — Efficient data structures

### 4.1 WHAT

Redis không chỉ "để dữ liệu trong RAM" — nó chọn **encoding khác nhau cho cùng một type tùy kích thước**:

| Type | Encoding nhỏ (compact) | Encoding lớn |
|---|---|---|
| String | `int`, `embstr` | `raw` (SDS) |
| Hash | `listpack` | `hashtable` |
| List | `listpack` (7.2+) | `quicklist` (linked list của listpack) |
| Set | `intset`, `listpack` (7.2+) | `hashtable` |
| Sorted Set | `listpack` | `skiplist` + `hashtable` |
| Stream | — | radix tree (`rax`) của listpack |

### 4.2 WHY

- **Nhỏ → mảng liên tục (listpack/intset)**: một vùng memory, không có pointer, cực ít overhead, **CPU cache-friendly** (quét tuần tự một mảng vài trăm byte nhanh hơn theo pointer qua hash table). Thao tác O(N) nhưng N nhỏ (≤128 mặc định) nên thực tế nhanh hơn O(1) có hằng số lớn.
- **Lớn → cấu trúc có index (hashtable/skiplist)**: đảm bảo complexity O(1)/O(log N) khi N lớn.

Ví dụ: một Hash 10 field lưu bằng listpack tốn ~100–200 byte; cùng dữ liệu bằng hashtable tốn ~1 KB (dictEntry + sds key + sds value + bucket array cho mỗi field).

### 4.3 Các tối ưu chi tiết khác

- **SDS** lưu độ dài → `STRLEN` O(1), append không cần quét, binary-safe ([Chương 7](07-sds.md)).
- **Shared integer objects** 0–9999: không cấp phát object mới cho số nhỏ (khi policy không phải LRU/LFU).
- **embstr**: robj và SDS nằm trong **một lần cấp phát** (≤ 64 byte) → một cache line tới hai, một lần malloc thay vì hai.
- **Incremental rehash**: không có lần "resize dừng thế giới" ([Chương 8](08-dict-hash-table.md)).
- **Skip list có span**: ZRANK O(log N) thay vì O(N) ([Chương 13](13-sorted-set.md)).

---

## 5. Nguyên nhân 3 — Single command-execution thread

### 5.1 WHAT

Tất cả lệnh được thực thi tuần tự trên main thread.

### 5.2 WHY — Tại sao single-thread lại nhanh

1. **Không có lock**: không mutex, không spinlock, không atomic CAS trên cấu trúc dữ liệu. Với lệnh chỉ tốn 1 µs, một mutex contended (vài µs khi phải vào kernel qua futex) sẽ **đắt hơn chính công việc**.
2. **Không có context switch** giữa các thread xử lý lệnh.
3. **CPU cache ấm**: dữ liệu nóng (bucket array, object hay dùng) nằm trong cache của **một** core. Với đa luồng, cùng một dict bị ghi từ nhiều core → cache line "ping-pong" giữa các core (cache coherence traffic, false sharing).
4. **Không có deadlock, không có lock ordering** → code đơn giản, ít bug, dễ tối ưu.
5. **Atomic miễn phí**: INCR, LPUSH, ZADD, MULTI/EXEC, Lua đều atomic mà không cần cơ chế gì thêm.

### 5.3 Giới hạn

- Execute bị giới hạn ở **một core**. Nếu workload CPU-bound (nhiều lệnh tính toán nặng: ZUNIONSTORE, SORT, Lua, SINTER lớn), thêm core không giúp.
- **Head-of-line blocking**: một lệnh O(N) lớn chặn mọi client ([Chương 3](03-event-loop.md)).

---

## 6. Nguyên nhân 4 — Event-driven & non-blocking I/O

### 6.1 WHAT

Socket ở chế độ non-blocking; event loop dùng `epoll_wait`/`kevent` để chỉ xử lý socket **đã sẵn sàng**.

### 6.2 WHY

- **O(số socket sẵn sàng)**, không phải O(tổng số socket): epoll trả về đúng danh sách fd có sự kiện. Với 10.000 connection mà chỉ 50 cái có request, Redis chỉ chạm 50 cái. (`select`/`poll` phải quét toàn bộ tập fd mỗi lần → O(N).)
- **Không bao giờ chờ trên một socket**: `read()` trả về ngay với dữ liệu có sẵn hoặc `EAGAIN`; `write()` ghi được bao nhiêu thì ghi, phần còn lại chờ socket writable.
- **Gom việc**: một lần `epoll_wait` có thể trả về hàng trăm fd; một lượt `beforeSleep` ghi reply cho nhiều client.

Chi tiết ở [Chương 3](03-event-loop.md).

---

## 7. Nguyên nhân 5 — Minimal protocol overhead: RESP

### 7.1 WHAT

RESP là giao thức text-based nhưng **có tiền tố độ dài**:

```
*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n
```

### 7.2 WHY nhanh

- **Tiền tố độ dài** (`$5`) → server biết trước cần đọc bao nhiêu byte, cấp phát đúng kích thước, **không cần quét tìm ký tự kết thúc** trong payload, và payload có thể chứa bất kỳ byte nào (binary-safe).
- **Parse cực đơn giản**: đọc một ký tự type, đọc số tới `\r\n`, đọc N byte. Không có JSON parsing, không có SQL grammar, không có planner.
- **Reply cũng đơn giản**: `+OK\r\n`, `:42\r\n`.
- So với SQL: PostgreSQL phải lex, parse, analyze, rewrite, plan, rồi execute — hàng chục µs chỉ cho phần trước execute với query đơn giản (dù có prepared statement giảm bớt).

Chi tiết ở [Chương 5](05-resp-protocol.md).

---

## 8. Nguyên nhân 6 — Efficient algorithms và amortization

Redis không chỉ chọn cấu trúc tốt mà **phân bổ chi phí lớn thành nhiều mẩu nhỏ** để không bao giờ có một khoảng dừng dài:

| Chi phí lớn | Cách Redis chia nhỏ |
|---|---|
| Resize hash table hàng triệu key | Incremental rehash: mỗi thao tác dời 1 bucket + 1 ms mỗi cron |
| Xóa key hết hạn hàng triệu | Active expire theo sampling, giới hạn % CPU mỗi chu kỳ |
| Giải phóng object 10 triệu phần tử | Lazy free trên BIO thread |
| Snapshot toàn bộ dataset | Fork child |
| Defragment memory | Active defrag theo lát cắt thời gian |
| Liệt kê toàn bộ keyspace | SCAN với cursor thay vì KEYS |

Nguyên tắc chung: **mọi việc có chi phí O(N) với N lớn phải được chia thành nhiều lát O(1)/O(ít) xen giữa các lệnh client**, hoặc đẩy ra khỏi main thread.

---

## 9. Nguyên nhân 7 — Pipelining & batching

### 9.1 WHAT

Client gửi nhiều lệnh liên tiếp **không chờ reply** của lệnh trước; server xử lý tuần tự và gửi reply theo đúng thứ tự.

### 9.2 WHY

Chi phí của một request không pipeline:
```
RTT (100–500 µs) + read syscall (~1–5 µs) + parse + execute (~1 µs) + write syscall (~1–5 µs)
```
Với pipeline 100 lệnh:
```
1 RTT + 1 vài read + 100 × (parse + execute) + 1 vài write
```
- **RTT** được chia cho 100 lệnh.
- **Syscall** được chia: một `read()` 16 KB chứa hàng chục lệnh; một `write()` chứa hàng chục reply.
- Theo Redis docs, không chỉ RTT mà **chi phí syscall/context switch** mới là lý do throughput tăng tới ~10x với pipelining ngay cả trên loopback.

Batching (MGET, MSET, HMGET, Lua) giảm thêm: một lệnh thay vì nhiều lệnh → ít lần parse/dispatch/reply header. Chi tiết ở [Chương 29](29-pipelining.md).

---

## 10. Nguyên nhân 8 — Những thứ Redis KHÔNG làm

Nhanh một phần vì **không làm**:
- Không fsync mỗi write (mặc định).
- Không chờ replica ack.
- Không MVCC, không undo log, không WAL theo nghĩa database (AOF là log lệnh, flush async).
- Không query planner, không cost estimation.
- Không kiểm tra constraint, foreign key, trigger (trừ keyspace notification rất nhẹ).
- Không nén mặc định trên đường nóng (chỉ LZF trong RDB, và tùy chọn nén node quicklist).

Mỗi thứ "không làm" là một **trade-off về durability/consistency/tính năng** — chính là giá phải trả cho tốc độ.

---

## 11. DATA FLOW — Phân rã 200 µs của một GET

```mermaid
flowchart LR
    A["App gọi client.get()"] --> B["Client lib: lấy connection từ pool, serialize RESP ~1-5 µs"]
    B --> C["write() syscall ~2-5 µs"]
    C --> D["Network: NIC, switch, NIC ~50-150 µs một chiều"]
    D --> E["Kernel Redis host: interrupt, TCP stack, wake epoll"]
    E --> F["Redis: read() ~1-3 µs, parse ~0.2 µs"]
    F --> G["Execute GET: hash, dict lookup, expire check ~0.3-1 µs"]
    G --> H["addReply + write() ~1-3 µs"]
    H --> I["Network trở về ~50-150 µs"]
    I --> J["Client: read(), parse, deserialize, trả cho app"]
```

**Cách đọc diagram:** Trong ~200 µs end-to-end, Redis thực sự "làm việc" (F+G+H) chỉ khoảng **2–7 µs**, và execute (G) thường **< 1 µs**. Phần còn lại là network và kernel ở cả hai đầu. Hệ quả thực hành:
- Redis có thể phục vụ ~150k–500k lệnh/s trên một thread về mặt CPU, nhưng **mỗi client** chỉ đạt ~5.000 lệnh/s nếu gửi tuần tự (1/200 µs).
- Muốn app nhanh hơn: giảm số round-trip, không phải tìm "Redis nhanh hơn".
- Nếu app thấy GET mất 5 ms mà `SLOWLOG` trống → vấn đề nằm ở network, hàng đợi phía client (pool cạn), GC của app, hoặc hàng đợi trong Redis do lệnh khác chiếm thread.

---

## 12. Redis 100k ops/s thực chất phụ thuộc vào gì

Khi ai đó nói "Redis chạy 100k ops/s", hãy hỏi lại **10 biến số** sau:

| Biến | Ảnh hưởng |
|---|---|
| **Loại lệnh** | GET/SET O(1) nhỏ vs ZRANGE 1000 phần tử vs Lua script: khác nhau 10–1000x |
| **Kích thước payload** | Value 100 B vs 100 KB: với 100 KB, 100k ops/s = 10 GB/s → vượt NIC 10/25 Gbps |
| **Pipelining depth** | 1 vs 16 vs 128: throughput khác nhau 5–10x |
| **Số connection đồng thời** | Quá ít → không đủ song song để lấp RTT; quá nhiều → overhead bookkeeping, memory |
| **Network** | Loopback vs cùng rack vs cross-AZ; virtualized NIC có overhead lớn |
| **TLS** | Mã hóa tốn CPU, có thể giảm throughput 30–60% nếu chạy trên main thread |
| **I/O threads** | Có thể tăng throughput đáng kể khi I/O là nút thắt (Redis 8.0 công bố +37% đến +112% với 8 thread tùy lệnh) |
| **Persistence** | AOF always: bị giới hạn bởi fsync (~vài nghìn/s trên HDD, vài chục nghìn/s SSD); fork định kỳ gây spike |
| **Replication** | Mỗi replica = thêm một luồng write ra socket |
| **CPU** | Tần số single-core, kích thước L3 cache, NUMA placement |

Benchmark `redis-benchmark` với `-P 16` trên loopback cho con số rất đẹp nhưng **không phản ánh production**, nơi RTT, TLS, payload thật và lệnh thật chiếm ưu thế.

---

## 13. WHAT HAPPENS IF — Các trường hợp Redis chậm

| Tình huống | Cơ chế làm chậm | Chương |
|---|---|---|
| Lệnh O(N) lớn: KEYS, HGETALL/SMEMBERS/LRANGE trên big key, SORT, ZUNIONSTORE lớn | Chiếm main thread hàng trăm ms → head-of-line blocking | 3, 55 |
| DEL big key | Giải phóng hàng triệu allocation trên main thread | 28 |
| Lua script dài | Atomic → chặn toàn bộ | 31 |
| Fork (BGSAVE, AOF rewrite, full sync) | Copy page table, COW page fault | 34, 35 |
| AOF fsync chậm | write() bị chặn | 36 |
| Swap | Page fault vào disk → ms mỗi lần | 21 |
| Transparent Huge Pages bật | COW copy 2 MB thay vì 4 KB, latency và memory tăng | 35 |
| Eviction hàng loạt khi chạm maxmemory | Mỗi lệnh ghi phải evict trước | 23 |
| Hàng loạt key hết hạn cùng lúc | Active expire chiếm tới 25% CPU mỗi chu kỳ | 20 |
| Hot key | Một node/một thread bão hòa | 27 |
| Nhiều connection mới liên tục (không pool) | Accept + TLS handshake + tạo client tốn CPU | 53 |
| Client đọc chậm | Output buffer phình, memory | 53 |
| Network saturation | Value lớn làm đầy NIC | 54 |
| Noisy neighbor / CPU steal trong VM | Main thread bị tước CPU | 52 |

---

## 14. PRODUCTION BEHAVIOR

- **Median latency ổn định, p99 nhảy vọt** là "chữ ký" của một hệ thống một thread bị chặn định kỳ. Nguồn phổ biến: fork, big key, lệnh O(N) từ job batch, active expire khi nhiều key cùng TTL.
- **"Redis chậm" thường là app chậm**: pool cạn → request chờ connection; GC pause của JVM/Go làm latency client-side cao; DNS; TLS handshake lại do connection bị đóng.
- **Đo đúng chỗ**: `redis-cli --latency` từ cùng host với app (đo RTT + service), `--intrinsic-latency` trên host Redis (đo độ trễ nội tại của OS/hypervisor), `SLOWLOG` (chỉ service time), `LATENCY DOCTOR` (sự kiện nội bộ như fork, fsync).

---

## 15. TRADE-OFF

| Nguồn tốc độ | Cái giá |
|---|---|
| RAM | Chi phí, dataset giới hạn, cần persistence riêng |
| Single thread execute | Một core; head-of-line blocking |
| Không fsync mỗi ghi | Có thể mất dữ liệu gần nhất |
| Async replication | Mất ghi đã ack khi failover |
| Không query engine | Mọi access pattern phải thiết kế trước bằng key/cấu trúc |
| Compact encoding | O(N) trên N nhỏ; chuyển encoding tốn CPU một lần |

---

## 16. COMMON MISUNDERSTANDINGS

| Hiểu sai | Thực tế |
|---|---|
| "Redis nhanh vì in-memory và single-threaded" | Đúng một phần; thiếu: data structure/encoding, event loop epoll, RESP, amortization, không fsync/không chờ replica. Và single-thread là **nguồn giới hạn** chứ không chỉ nguồn tốc độ |
| "GET luôn O(1) nên luôn nhanh" | GET một string 50 MB phải copy 50 MB vào buffer và đẩy qua mạng; GET có thể phải chờ lệnh khác |
| "Thêm CPU thì Redis nhanh hơn" | Không cho phần execute; chỉ giúp I/O threads, fork child, BIO |
| "Benchmark 1M ops/s nghĩa là app của tôi sẽ đạt" | Benchmark dùng pipeline, loopback, payload nhỏ |
| "Latency Redis = service time trong SLOWLOG" | SLOWLOG không tính thời gian chờ hàng đợi, network, đọc/ghi socket |

---

## 17. INTERVIEW QUESTIONS

1. **Why is Redis fast?**
   → Trả lời nhiều tầng: (1) dữ liệu trong RAM, không có disk trên read path; (2) cấu trúc dữ liệu tối ưu và encoding compact cho object nhỏ; (3) một thread thực thi → không lock, cache ấm, atomic tự nhiên; (4) event loop epoll non-blocking, O(số socket sẵn sàng); (5) RESP có length prefix, parse rẻ; (6) chi phí lớn được chia nhỏ (incremental rehash, active expire, lazy free, fork); (7) pipelining/batching chia RTT và syscall; (8) không fsync/không chờ replica mặc định. Kết thúc bằng: **và nó chậm khi nào**.
2. **Nếu Redis execute chỉ mất 1 µs, tại sao app thấy GET mất 300 µs?**
   → RTT, syscall, kernel network stack, client library, thời gian chờ trong hàng đợi.
3. **Làm sao tăng throughput khi Redis CPU main thread 95%?**
   → Tìm lệnh đắt (`INFO commandstats`, SLOWLOG); giảm lệnh O(N); pipeline để giảm chi phí per-request; bật I/O threads nếu phần lớn CPU là I/O/TLS; tách workload sang instance khác; Redis Cluster để scale-out.
4. **Tại sao pipelining tăng throughput ngay cả trên loopback (RTT ~ 0)?**
   → Giảm syscall read/write và context switch trên mỗi lệnh.
5. **(Senior) Redis ở 90% CPU main thread có vấn đề gì dù latency median vẫn thấp?**
   → Theo lý thuyết hàng đợi, thời gian chờ tăng phi tuyến khi utilization gần 1; mọi spike nhỏ (fork, expire, lệnh chậm) sẽ khuếch đại thành p99 rất cao; không còn headroom.

---

## 18. KEY TAKEAWAYS

- Redis nhanh vì **tổ hợp** nhiều quyết định: RAM, encoding compact, một thread không lock, epoll, RESP, amortization, pipelining — và **không làm** fsync/sync replication mặc định.
- **Service time ≪ latency**: phần lớn thời gian là network và syscall → tối ưu bằng cách giảm round-trip.
- **Single-thread vừa là nguồn tốc độ vừa là giới hạn**: mọi thứ chậm trên main thread là sự cố toàn cục.
- Khi đánh giá "Redis X ops/s", luôn hỏi: lệnh gì, payload bao nhiêu, pipeline bao sâu, network nào, TLS, persistence, replication.
- Tail latency (p99/p999) là thước đo sức khỏe thật của Redis trong production.
