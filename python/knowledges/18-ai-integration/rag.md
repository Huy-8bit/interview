# Retrieval-Augmented Generation (RAG)

> **Phạm vi phỏng vấn:** AI Integration · **Ưu tiên:** P0/P1 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

RAG truy xuất evidence liên quan rồi đưa vào prompt để LLM trả lời grounded trên dữ liệu riêng/cập nhật.

## 2. Why does it matter?

Senior Engineer cần hiểu **Retrieval-Augmented Generation (RAG)** để kiểm soát latency, quality, privacy và chi phí của dependency xác suất. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Ingestion parse/chunk/embed/index; query embed/retrieve/filter/rerank; generation trích citation. Đánh giá retrieval recall riêng với answer quality và chống prompt injection từ document.

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

**Retrieval-Augmented Generation (RAG)** cần thêm tenant ACL, model version, token budget, citation và quality evaluation ở production.

## 5. Production Use Case

Chatbot hướng dẫn kỹ thuật lọc theo model xe/version/ACL, hybrid retrieve top-50, rerank top-8, trả citation và abstain khi evidence yếu.

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
| Tối ưu/thiết kế xoay quanh Retrieval-Augmented Generation (RAG) | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is Retrieval-Augmented Generation (RAG), and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind Retrieval-Augmented Generation (RAG).
- **B3.** Which guarantees does Retrieval-Augmented Generation (RAG) provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of Retrieval-Augmented Generation (RAG)?
- **B5.** What is the most common misconception about Retrieval-Augmented Generation (RAG)?
- **B6.** How would you test assumptions involving Retrieval-Augmented Generation (RAG)?
- **B7.** Which edge cases or failure modes matter most for Retrieval-Augmented Generation (RAG)?
- **B8.** How can Retrieval-Augmented Generation (RAG) affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of Retrieval-Augmented Generation (RAG)?
- **B10.** When is a different or simpler approach better than relying on Retrieval-Augmented Generation (RAG)?

### Production Scenarios (5)

- **S1.** Answers are fluent but cite irrelevant chunks. How do you separate retrieval quality from generation quality?
- **S2.** A document contains prompt injection asking the model to expose other tenants. Where are the trust boundaries?
- **S3.** Changing embedding models reduces recall for Vietnamese automotive terms. Design versioned migration and evaluation.
- **S4.** Context exceeds the model window. Choose chunking, reranking, compression, and abstention behavior.
- **S5.** Vector search is healthy but time-to-first-token doubles. How do traces and token budgets localize the issue?

## 9. Senior-level Questions

- **L1.** How does Retrieval-Augmented Generation (RAG) constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when Retrieval-Augmented Generation (RAG) meets concurrency or partial failure?
- **L3.** What breaks first around Retrieval-Augmented Generation (RAG) at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using Retrieval-Augmented Generation (RAG)?
- **L5.** How would you benchmark or validate Retrieval-Augmented Generation (RAG) without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can Retrieval-Augmented Generation (RAG) introduce?
- **L7.** How would you change a poor decision around Retrieval-Augmented Generation (RAG) with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for Retrieval-Augmented Generation (RAG)?
- **L10.** How would you turn an incident involving Retrieval-Augmented Generation (RAG) into a durable prevention mechanism?

## 10. Short Answers

**B1.** RAG truy xuất evidence liên quan rồi đưa vào prompt để LLM trả lời grounded trên dữ liệu riêng/cập nhật. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của Retrieval-Augmented Generation (RAG).

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo time-to-first-token, groundedness, token cost, retrieval recall và fallback rate; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng Retrieval-Augmented Generation (RAG) như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh Retrieval-Augmented Generation (RAG) khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của Retrieval-Augmented Generation (RAG)**, không chỉ “dùng để làm gì”.
- Định lượng bằng time-to-first-token, groundedness, token cost, retrieval recall và fallback rate và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

RAG là search system đứng trước generation system. Nếu retrieval không lấy đúng evidence, prompt hay hơn cũng không cứu được groundedness.

## 14. Internals Deep Dive


Ingestion phải version parse/chunk/embedding/index và giữ lineage từ chunk về document/page/ACL. Query path normalize/rewrite khi cần, hybrid retrieve candidate, metadata/ACL filter, rerank, pack context theo token budget rồi generate với citation/abstention.

Đánh giá retrieval bằng recall@k/MRR trên labeled queries; đánh giá answer bằng groundedness/citation correctness/task success. ANN similarity không bảo đảm fact. Document là untrusted input: prompt injection phải bị cô lập bằng instruction hierarchy, allowlisted tool, ACL enforcement ngoài model và output validation.


Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart LR
    Query --> Embed["Query embedding"]
    Embed --> Retrieve["Hybrid retrieval + ACL filter"]
    Retrieve --> Rerank
    Rerank --> Pack["Context packing"]
    Pack --> Prompt["Versioned prompt"]
    Prompt --> LLM
    LLM --> Validate["Citation / policy validation"]
    Validate --> Stream
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

1. **What guarantee does Retrieval-Augmented Generation (RAG) provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **Retrieval-Augmented Generation (RAG)** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [Vector Database](vector-database.md)
- [AI Observability](ai-observability.md)
- [AI Chatbot Design](../11-system-design/design-ai-chatbot.md)
