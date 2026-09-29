# AI Scalability

> **Phạm vi phỏng vấn:** AI Integration · **Ưu tiên:** P0/P1 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

AI scalability tối ưu đồng thời compute/provider quota, token throughput, retrieval latency, quality và cost per successful answer.

## 2. Why does it matter?

Senior Engineer cần hiểu **AI Scalability** để kiểm soát latency, quality, privacy và chi phí của dependency xác suất. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Phân tách online/offline, batch embedding, cache theo version/ACL, route model theo complexity, cap output token và shed/admit theo tenant. Autoscale không vượt DB/vector/provider/GPU capacity.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `time-to-first-token, groundedness, token cost, retrieval recall và fallback rate` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class RetrievedChunk:
    document_id: str
    text: str
    score: float

def select_context(chunks: list[RetrievedChunk], *, min_score: float = 0.72) -> list[RetrievedChunk]:
    allowed = (chunk for chunk in chunks if chunk.score >= min_score)
    return sorted(allowed, key=lambda chunk: chunk.score, reverse=True)[:8]
```

**AI Scalability** cần thêm tenant ACL, model version, token budget, citation và quality evaluation ở production.

## 5. Production Use Case

Chatbot dùng small model cho classification, premium model chỉ cho complex query; semantic cache có tenant/prompt/model version và không dùng cho sensitive answer.

Checklist triển khai: capacity budget, timeout, idempotency (nếu có side effect), telemetry, canary, rollback và reconciliation.

## 6. Common Problems

- Không định nghĩa invariant và source of truth trước khi chọn công nghệ.
- Retry không backoff/jitter làm traffic amplification khi dependency lỗi.
- Không có bound cho queue, connection, memory hoặc concurrency.
- Chỉ theo dõi average; bỏ qua p95/p99, saturation và error semantics.
- Rollout toàn bộ, thiếu feature flag/canary và đường rollback dữ liệu.

## 7. Trade-offs

| Lựa chọn | Lợi ích | Chi phí / rủi ro | Khi phù hợp |
|---|---|---|---|
| Tối ưu/thiết kế xoay quanh AI Scalability | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is AI Scalability, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind AI Scalability.
- **B3.** Which guarantees does AI Scalability provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of AI Scalability?
- **B5.** What is the most common misconception about AI Scalability?
- **B6.** How would you test assumptions involving AI Scalability?
- **B7.** Which edge cases or failure modes matter most for AI Scalability?
- **B8.** How can AI Scalability affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of AI Scalability?
- **B10.** When is a different or simpler approach better than relying on AI Scalability?

### Production Scenarios (5)

- **S1.** A release involving AI Scalability triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around AI Scalability is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to AI Scalability. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving AI Scalability fails first?
- **S5.** A canary changes the behavior of AI Scalability; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does AI Scalability constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when AI Scalability meets concurrency or partial failure?
- **L3.** What breaks first around AI Scalability at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using AI Scalability?
- **L5.** How would you benchmark or validate AI Scalability without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can AI Scalability introduce?
- **L7.** How would you change a poor decision around AI Scalability with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for AI Scalability?
- **L10.** How would you turn an incident involving AI Scalability into a durable prevention mechanism?

## 10. Short Answers

**B1.** AI scalability tối ưu đồng thời compute/provider quota, token throughput, retrieval latency, quality và cost per successful answer. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của AI Scalability.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo time-to-first-token, groundedness, token cost, retrieval recall và fallback rate; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng AI Scalability như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh AI Scalability khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của AI Scalability**, không chỉ “dùng để làm gì”.
- Định lượng bằng time-to-first-token, groundedness, token cost, retrieval recall và fallback rate và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Hãy xem **AI Scalability** như một boundary biến input/state thành output. Muốn hiểu sâu phải chỉ ra ai sở hữu state, lifecycle, điểm contention và behavior khi dependency chậm hoặc mất.

## 14. Internals Deep Dive

Model là dependency xác suất có quota, token cost và quality drift. Version data/model/prompt, đo system + quality, enforce ACL ngoài model và luôn có abstention/fallback.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart LR
            Input --> Guard["Auth + policy"] --> Topic["AI Scalability"]
            Topic --> Model["Versioned model / provider"]
            Model --> Validate["Quality + schema validation"]
            Validate --> Output
            Topic --> Telemetry["Latency + tokens + quality"]
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Provider timeout, retrieval miss hoặc prompt injection có thể vẫn trả HTTP 200 nhưng answer sai. Có abstention, citation/ACL validation, fallback và evaluation/replay theo version.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Tách system latency khỏi retrieval/model quality.
2. Trace retrieval/rerank/prompt/provider/stream.
3. Kiểm model/prompt/index/data version và ACL.
4. Đo tokens/quota/retry/fallback.
5. Replay golden set và affected slice.

## 18. Common Misconceptions

**Sai:** HTTP 200 và answer trôi chảy nghĩa AI đúng. **Đúng:** phải đo retrieval, groundedness, citation, safety, cost và task success.

## 19. When NOT to use

Không dùng LLM khi rule/search/deterministic parser đáp ứng accuracy, latency và cost tốt hơn.

## 20. What interviewer may ask next

1. **What guarantee does AI Scalability provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **AI Scalability** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [RAG](rag.md)
- [Vector Database](vector-database.md)
- [AI Observability](ai-observability.md)
- [AI Chatbot Design](../11-system-design/design-ai-chatbot.md)
