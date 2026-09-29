# Caching trong system design

## Bài toán và ví dụ đầu tiên

Repeated reads làm DB bận trong khi dữ liệu ít đổi. Cache có thể giảm latency và load nhưng thêm bản sao có thể stale. Thiết kế bắt đầu từ dữ liệu nào cache được và người dùng chịu cũ bao lâu.

## Đi từng bước qua một tình huống

V1 đọc DB; V2 cache-aside cho key hot, TTL/version và invalidation policy. Khi miss, request cần bounded loader để cache-down không tạo stampede. Negative cache và coalescing có thể giảm work trùng nhưng phải scope key đúng tenant/filter.

## Hiểu cơ chế từ kết quả quan sát

Write/invalidate/read-fill có race nên TTL không là consistency mạnh. Cache size phải bound theo bytes/cardinality, không chỉ TTL. Hệ thống vẫn phải xử lý authoritative reads cho action cần state mới như permission/payment theo contract.

## Khái niệm và mô hình làm việc

Cache cần xác định key, owner, freshness, eviction, failure fallback và invalidation race.

## Cơ chế và những ranh giới cần giữ

Model hit/miss separately; TTL+jitter, bounded memory, negative caching và coalescing. Read-through/write-through names không thay correctness proof.

## Áp dụng vào hệ thống thật

Catalog read cache reduce DB load, authorization state cần strict freshness theo security policy.

## Những đường lỗi cần hiểu

Hot-key expiry stampede, cross-tenant key collision, stale refill và Redis down overload source.

## Lần theo bằng chứng khi có sự cố

Hit ratio by route, age/version, source load và evictions; test cold-cache load.

## Đánh đổi và giới hạn sử dụng

Không thêm cache khi miss path không chịu nổi recovery; source budget là điều kiện thiết kế.

## Thực hành, debugging và kết luận

Load test cache hit bình thường, cold start và outage. Đo hit ratio, freshness, DB miss load và eviction. Chỉ thêm cache sau khi query/index và access pattern rõ; một cache lớn không sửa write bottleneck hoặc invariant sai.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
