# Kafka broker image = official apache/kafka + Prometheus JMX exporter java agent.
# The agent runs inside the broker JVM and exposes broker metrics on :7071/metrics.
ARG KAFKA_VERSION=4.3.1
FROM apache/kafka:${KAFKA_VERSION}

ARG JMX_EXPORTER_VERSION=1.0.1
USER root
RUN mkdir -p /opt/jmx \
 && wget -q -O /opt/jmx/jmx_prometheus_javaagent.jar \
    "https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar"
COPY config/jmx-exporter.yml /opt/jmx/kafka.yml
# Small wrapper so CLI tools inside the container do not inherit the broker's
# KAFKA_OPTS (the javaagent would try to bind :7071 a second time) or its heap.
COPY config/kt /usr/local/bin/kt
RUN chmod +x /usr/local/bin/kt && chown -R appuser:root /opt/jmx
USER appuser
