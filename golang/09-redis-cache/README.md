# Redis Cache

Cache là hệ consistency/failure có source capacity budget.

## Reading map

| Bài | Ưu tiên |
|---|---|
| [Cache-aside: miss path cũng là production path](cache-aside.md) | P1 |
| [Cache stampede và refresh coalescing](cache-stampede.md) | P1 |
| [Caching patterns và consistency](caching-patterns.md) | P1 |
| [Redis lock và fencing](distributed-lock.md) | P1 |
| [Redis failure game day](failure-scenarios.md) | P1 |
| [Redis atomic rate limiting](rate-limiting.md) | P1 |
| [Redis: data structures và bounded memory](redis-basics.md) | P1 |
| [Redis Cluster: slots và hot keys](redis-cluster.md) | P1 |

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
