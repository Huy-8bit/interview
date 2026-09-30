"""Celery over a three-node RabbitMQ cluster, one quorum work queue.

RabbitMQ carries commands ("render the report for inspection X") to exactly one
worker each. Business facts produced afterwards still go through the Kafka outbox.
"""
from celery import Celery
from kombu import Exchange, Queue

from app.reports.settings import ReportSettings

TASK_NAME = "inspection.generate_report"
QUEUE = "inspection.report.generate"
ROUTING_KEY = "report.generate"
DLQ = "inspection.report.dlq"
# Topic exchange: Celery's native delayed delivery (retry countdowns on quorum queues)
# re-routes messages with a bit-encoded prefix, which a direct exchange cannot match.
EXCHANGE = Exchange("inspection.reports", type="topic", durable=True)
# Quorum queues have two priority levels: 5..255 is high, 0..4 is normal.
HIGH_PRIORITY, NORMAL_PRIORITY = 9, 0

settings = ReportSettings()
celery_app = Celery("inspection-reports")
celery_app.conf.update(
    broker_url=settings.rabbitmq_urls,
    broker_failover_strategy="shuffle",
    broker_heartbeat=settings.rabbitmq_heartbeat,
    broker_connection_timeout=3,
    broker_connection_retry_on_startup=True,
    # Publisher confirms: send_task returns only after the quorum queue has the
    # message on a majority of nodes, so the dispatcher may mark the row QUEUED.
    broker_transport_options={"confirm_publish": True},
    # Must match infrastructure/rabbitmq/init-topology.py exactly (x-arguments).
    task_queues=[Queue(QUEUE, EXCHANGE, routing_key=ROUTING_KEY, queue_arguments={"x-queue-type": "quorum"})],
    task_default_queue=QUEUE,
    task_routes={TASK_NAME: {"queue": QUEUE, "routing_key": ROUTING_KEY}},
    task_create_missing_queues=False,
    task_serializer="json",
    accept_content=["json"],
    # Business state lives in inspection_reports; no Celery result backend.
    task_ignore_result=True,
    # ACK only after the task returns. A crashed/killed worker leaves the message
    # unacked and RabbitMQ redelivers it; a failed task is rejected -> DLX -> DLQ.
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    task_acks_on_failure_or_timeout=False,
    task_soft_time_limit=settings.report_soft_time_limit,
    task_time_limit=settings.report_time_limit,
    # One message per process: long tasks are not hoarded by a busy worker.
    worker_prefetch_multiplier=1,
    worker_cancel_long_running_tasks_on_connection_loss=True,
    # Exclusive control/event queues: RabbitMQ 4.x deprecates transient non-exclusive queues.
    control_queue_exclusive=True,
    event_queue_exclusive=True,
    worker_send_task_events=False,
    task_send_sent_event=False,
)
