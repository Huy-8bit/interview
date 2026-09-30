"""Deterministic inspection report rendering: a real one-page PDF plus emulated cost."""
import hashlib
import time
from dataclasses import dataclass

TITLES = {"CERTIFICATE": "INSPECTION CERTIFICATE", "DEFECT_REPORT": "INSPECTION DEFECT REPORT"}


@dataclass(frozen=True)
class Document:
    pdf: bytes
    sha256: str
    report_number: str


def snapshot(report, inspection, vehicle, warranty):
    """Copy everything the renderer needs while the claim transaction is open."""
    payload = (vehicle.vehicle_payload or {}) if vehicle else {}
    return {
        "inspection_id": str(inspection.id),
        "vehicle_id": str(inspection.vehicle_id),
        "kind": report.kind,
        "result": inspection.result,
        "inspection_type": inspection.inspection_type,
        "failure_reason": inspection.failure_reason,
        "completed_at": inspection.completed_at.isoformat(),
        "vin": payload.get("vin"),
        "vehicle": " ".join(str(payload[k]) for k in ("manufacturer", "model", "production_year") if payload.get(k)),
        "owner_name": payload.get("owner_name"),
        "warranty_id": str(warranty.warranty_id) if warranty else None,
        "warranty": f"{warranty.warranty_type} {warranty.warranty_status} until {warranty.end_date}" if warranty else "none on record",
    }


def report_number(data):
    return f"IR-{data['completed_at'][:10].replace('-', '')}-{data['inspection_id'][:8].upper()}"


def _escape(value):
    text = str(value).encode("latin-1", "replace").decode("latin-1")
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def _pdf(lines):
    content = "BT /F1 11 Tf 56 790 Td 16 TL " + " ".join(f"({_escape(line)}) Tj T*" for line in lines) + " ET"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        f"<< /Length {len(content.encode('latin-1'))} >>\nstream\n{content}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    body, offsets = b"%PDF-1.4\n", []
    for number, item in enumerate(objects, start=1):
        offsets.append(len(body))
        body += f"{number} 0 obj\n{item}\nendobj\n".encode("latin-1")
    xref = len(body)
    body += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    body += "".join(f"{offset:010d} 00000 n \n" for offset in offsets).encode()
    body += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return body


def _layout_cost(seed, cost_ms):
    """Burn real CPU for cost_ms so worker scaling, CPU and latency are observable.

    Only the time budget matters; the digest is not part of the document, so a
    redelivered task still produces byte-identical output.
    """
    deadline = time.perf_counter() + cost_ms / 1000
    digest = seed
    while time.perf_counter() < deadline:
        for _ in range(500):
            digest = hashlib.sha256(digest).digest()


def render(data, cost_ms):
    number = report_number(data)
    lines = [
        TITLES[data["kind"]], "", f"Report number: {number}", f"Inspection: {data['inspection_id']}",
        f"Type: {data['inspection_type']}    Result: {data['result']}", f"Completed at: {data['completed_at']}", "",
        f"Vehicle: {data['vehicle'] or 'unknown'}", f"VIN: {data['vin'] or 'unknown'}", f"Owner: {data['owner_name'] or 'unknown'}",
        f"Warranty: {data['warranty']}", "",
    ]
    if data["result"] == "FAIL":
        lines += ["Defect found:", f"  {data['failure_reason']}", "Vehicle must be repaired before the next road use."]
    else:
        lines += ["No defect found. The vehicle passed this inspection."]
    _layout_cost(data["inspection_id"].encode(), cost_ms)
    pdf = _pdf(lines)
    return Document(pdf=pdf, sha256=hashlib.sha256(pdf).hexdigest(), report_number=number)
