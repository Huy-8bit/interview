# Monitoring configuration

Hướng dẫn đầy đủ: [Observability lab](../docs/OBSERVABILITY.md).

- `prometheus/prometheus.yml`: scrape thật, DNS discovery cho các API replicas, Redis multi-target.
- `prometheus/rules/lab.yml`: example alerts, xem tại Prometheus `/alerts`.
- `grafana/provisioning`: datasource UID `lab-prometheus` và file provider.
- `grafana/dashboards`: 10 dashboard JSON, tự load khi Compose khởi động.
- `generate_dashboards.py`: nguồn sinh dashboard, chạy `python monitoring/generate_dashboards.py` trong toolbox hoặc Python local.
- `exporters/jmx.yml`: allowlist Kafka/Connect/Debezium MBeans, JMX javaagent 1.3.0 được pin SHA256 trong Dockerfiles.
- `exporters/postgres-queries.yml`: truy vấn pg_monitor cho WAL/replication/slots/activity; không đọc business rows.
- `exporters/platform_exporter.py`: chỉ đọc Connect REST và Kafka Admin assignment; không truy cập application databases.
- `exporters/check_targets.py`: startup gate kiểm target UP thật.

Metric names và PromQL được kiểm bằng `make monitoring-check`; kết quả validation nằm trong docs/evidence/observability sau khi chạy kiểm chứng. Thay metric/exporter version phải kiểm lại dashboard queries.

Nguồn tham khảo chính thức: [Prometheus scrape config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/), [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/), [JMX agent](https://prometheus.github.io/jmx_exporter/1.3.0/deployment/java-agent/), [Kafka exporter](https://github.com/danielqsj/kafka_exporter), [Redis exporter](https://github.com/oliver006/redis_exporter), [Postgres exporter](https://github.com/prometheus-community/postgres_exporter), [cAdvisor](https://github.com/google/cadvisor), [Debezium PostgreSQL](https://debezium.io/documentation/reference/3.2/connectors/postgresql.html).
