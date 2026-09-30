"""RabbitMQ + Celery report pipeline against the running stack."""
import pytest

from scripts.lab_client import poll

pytestmark = pytest.mark.integration


async def test_fail_inspection_gets_one_defect_report_via_rabbitmq_and_repair_references_it(client, db):
    vehicle = await client.vehicle()
    await client.warranty(vehicle["id"])
    inspection = await client.inspection(vehicle["id"])
    await client.complete(inspection["id"], "FAIL")
    path = f"/inspections/{inspection['id']}/report"

    async def report():
        return (await client.request("inspection", "GET", path)).json()

    generated = await poll(report, lambda r: r.get("status") == "GENERATED", timeout=90)
    assert generated["kind"] == "DEFECT_REPORT" and generated["priority"] == "HIGH" and generated["attempts"] >= 1
    pdf = await client.request("inspection", "GET", path + ".pdf")
    assert pdf.status_code == 200 and pdf.headers["content-type"] == "application/pdf" and pdf.content.startswith(b"%PDF")
    assert pdf.headers["etag"].strip('"') == generated["sha256"]
    events = await db("inspection", "SELECT count(*) AS n FROM outbox_events WHERE event_type = 'inspection.report.generated' "
                                    "AND payload->'data'->>'inspection_id' = :id", id=inspection["id"])
    assert events[0]["n"] == 1

    async def repair():
        rows = await db("repair", "SELECT defect_report_sha256 FROM repair_requests WHERE inspection_id = CAST(:id AS uuid)", id=inspection["id"])
        return rows[0]["defect_report_sha256"] if rows else None

    assert await poll(repair, timeout=90) == generated["sha256"]  # Fact propagated over Kafka.


async def test_report_endpoints_distinguish_missing_inspection_from_missing_report(client):
    missing = await client.request("inspection", "GET", "/inspections/00000000-0000-0000-0000-000000000000/report")
    assert missing.status_code == 404 and missing.json()["error"]["code"] == "inspection_not_found"
