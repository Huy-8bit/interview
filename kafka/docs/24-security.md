# 24 — Security: PLAINTEXT, TLS, SASL, ACL

Lab chạy **PLAINTEXT** (và chỉ bind `127.0.0.1`) để tập trung vào cơ chế Kafka. Doc này mô tả cấu hình production và cách bật thử.

## Các security protocol (theo listener)

| Protocol | Mã hoá đường truyền | Xác thực | Dùng khi |
|---|---|---|---|
| `PLAINTEXT` | ❌ | ❌ | lab / mạng hoàn toàn tin cậy (gần như không bao giờ trong production) |
| `SSL` | ✅ TLS | tuỳ chọn mTLS (client cert) | mTLS trong service mesh / PKI nội bộ |
| `SASL_PLAINTEXT` | ❌ | ✅ SASL | không khuyến nghị (mật khẩu đi plaintext với PLAIN) |
| `SASL_SSL` | ✅ | ✅ SASL | **khuyến nghị** cho client |

SASL mechanisms: `PLAIN` (user/password, phải đi trên TLS), `SCRAM-SHA-256/512` (password băm, lưu trong metadata KRaft), `GSSAPI` (Kerberos), `OAUTHBEARER` (OIDC token — hợp với cloud/IdP).

## Ví dụ cấu hình SASL_SSL (production-style)

```properties
listeners=INTERNAL://:9093,EXTERNAL://:9094,CONTROLLER://:9095
listener.security.protocol.map=INTERNAL:SASL_SSL,EXTERNAL:SASL_SSL,CONTROLLER:SSL
inter.broker.listener.name=INTERNAL
sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
sasl.enabled.mechanisms=SCRAM-SHA-512,OAUTHBEARER
ssl.keystore.location=/etc/kafka/secrets/broker.keystore.jks
ssl.truststore.location=/etc/kafka/secrets/truststore.jks
ssl.client.auth=required               # cho listener controller (mTLS giữa controller/broker)
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer   # KRaft
super.users=User:admin;User:broker
allow.everyone.if.no.acl.found=false
```
Tạo user SCRAM (KRaft lưu credential trong metadata log):
```bash
kafka-storage.sh format ... --add-scram 'SCRAM-SHA-512=[name=admin,password=...]'     # bootstrap
kafka-configs.sh --bootstrap-server ... --alter --add-config 'SCRAM-SHA-512=[password=...]' --entity-type users --entity-name payment-svc
```
franz-go client: `kgo.DialTLSConfig(...)` + `kgo.SASL(scram.Auth{User:..., Pass:...}.AsSha512Mechanism())`.

## ACL — nguyên tắc tối thiểu

```bash
# payment-service: đọc orders bằng group payment-group, ghi payments, idempotent producer
kafka-acls.sh --add --allow-principal User:payment-svc --operation Read  --topic orders
kafka-acls.sh --add --allow-principal User:payment-svc --operation Read  --group payment-group
kafka-acls.sh --add --allow-principal User:payment-svc --operation Write --operation Describe --topic payments
# transactional producer cần thêm:
kafka-acls.sh --add --allow-principal User:txn-svc --operation Write --operation Describe --transactional-id txn-processor- --resource-pattern-type prefixed
```
Resource types: Topic, Group, Cluster, TransactionalId, DelegationToken. Dùng prefixed ACL theo quy ước đặt tên (`payments.` ...).

## Khác

- **Encryption at rest**: mã hoá disk/volume (Kafka không tự mã hoá log). Dữ liệu nhạy cảm: mã hoá field ở producer (envelope encryption) — lưu ý DLQ cũng chứa payload.
- **Quotas**: chống một client chiếm hết băng thông (`producer_byte_rate`, `consumer_byte_rate`, `request_percentage`).
- **Audit**: authorizer logger, Kafka UI RBAC (lab mở không auth — chỉ bind localhost).
- **TLS làm mất zero-copy** (dữ liệu phải qua user space để mã hoá) → CPU broker tăng; dùng JDK mới, cipher AES-GCM có tăng tốc phần cứng.
- **Schema Registry / Kafka UI / Prometheus** cũng cần auth + TLS trong production.

## Optional secure profile

Lab không bật sẵn security để giữ việc học đơn giản. Cách thử nhanh SASL/PLAIN cục bộ: thêm một listener `SASL_PLAINTEXT` trên port khác cho *một* broker với `KAFKA_LISTENER_NAME_SECURE_PLAIN_SASL_JAAS_CONFIG` và `KAFKA_SASL_ENABLED_MECHANISMS=PLAIN`; image `apache/kafka` hỗ trợ cấu hình JAAS qua env (KAFKA_OPTS phải chứa `java.security.auth.login.config` theo script `configure` của image). Hãy làm trên một bản copy của compose — đổi listener của cluster đang chạy đòi hỏi restart rolling.

## INTERVIEW
1. SSL vs SASL_SSL? Vì sao không dùng SASL_PLAINTEXT với PLAIN?
2. ACL tối thiểu cho một consumer group?
3. Vì sao TLS ảnh hưởng hiệu năng broker?
4. Bảo vệ PII trong Kafka thế nào (kể cả DLQ, compacted topic, GDPR delete)?
