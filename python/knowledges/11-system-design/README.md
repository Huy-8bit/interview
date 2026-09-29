# System Design

    ## Learning order

    [Framework](system-design-framework.md) → [Capacity Estimation](capacity-estimation.md) → [Caching](caching.md) → [Database Scaling](database-scaling.md) → [Message Queue](message-queue.md) → [Observability](observability.md).

    ## Must know

    - Requirement/SLO/consistency và capacity estimate có đơn vị.
    - API/data model/source of truth trước component list.
    - V1 đơn giản → bottleneck đo được → V2/V3 có trade-off.
    - Timeout/retry/idempotency/backpressure/degraded mode/reconciliation.
    - Security, observability, RPO/RTO, cost và interview narrative.

    ## Recommended exercise

    Làm mỗi bài có timer 35 phút: 5 phút clarify/estimate, 20 phút architecture + deep dive, 10 phút failure/security/trade-off. Tự vẽ đủ high-level, sequence, data/source-of-truth, scaling và failure flow.

    ## Design Drills

    - [AI Chatbot Platform](design-ai-chatbot.md)
- [Intelligent Document Processing System](design-document-processing.md)
- [Vehicle Inspection Platform](design-vehicle-inspection.md)
- [Vehicle Warranty System](design-vehicle-warranty.md)
- [Manufacturing Production Planning System](design-production-planning.md)
- [Video Analytics Platform](design-video-processing.md)
- [Large-scale Notification System](design-notification-system.md)
- [Distributed File Processing System](design-file-processing.md)
- [Real-time WebSocket Platform](design-realtime-websocket.md)
- [Task Processing Platform](design-task-processing.md)
- [Large-scale Chat System](design-chat-system.md)

    Mỗi bài gồm requirement, scale, API, data model, architecture Mermaid, database/cache/queue/storage, scaling, failure, security, observability, bottleneck và future improvement.

    [← Main Dashboard](../README.md)
