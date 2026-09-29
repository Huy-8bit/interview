# PostgreSQL Cheatsheet

## Index
- B-tree: `=`, range, `ORDER BY`; composite theo left prefix.
- Partial: nhỏ hơn khi predicate ổn định. `INCLUDE`: covering, đổi write/storage.
- GIN: array/JSONB/full text. GiST: range/geometry. BRIN: bảng rất lớn, correlated physical order.

## EXPLAIN
- `EXPLAIN (ANALYZE, BUFFERS, WAL)` thực thi query.
- Xem estimate vs actual, loops, rows removed, sort spill, shared hit/read.

## MVCC / Transaction
- UPDATE tạo tuple version; long transaction giữ dead tuple → bloat.
- Read Committed snapshot/statement; Repeatable Read snapshot/transaction; Serializable có abort → retry whole transaction.
- Pool là admission control. Budget = replicas × workers × pool; pool không tăng DB capacity.
