"""Extract Mermaid sources and verify documentation using only Python's stdlib."""

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
ARTIFACTS = DOCS / "diagrams"
BLOCK = re.compile(r"```mermaid\n(.*?)\n```", re.DOTALL)
IDENTIFIER = re.compile(r"^\s*%% diagram: ([a-z][a-z0-9-]*)\s*$", re.MULTILINE)
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def diagrams():
    found = {}
    for document in sorted(DOCS.glob("*.md")):
        content = document.read_text()
        for match in BLOCK.finditer(content):
            source = match.group(1).strip() + "\n"
            names = IDENTIFIER.findall(source)
            if len(names) != 1 or names[0] in found:
                raise ValueError(f"Missing or duplicated diagram ID in {document.name}")
            identity = names[0]
            headings = re.findall(r"^#{1,6}\s+(.+)$", content[: match.start()], re.MULTILINE)
            found[identity] = {
                "id": identity,
                "document": document.name,
                "heading": headings[-1],
                "source_sha256": sha(source.encode()),
                "source": source,
            }
    return found


def extract():
    sources = ARTIFACTS / "sources"
    sources.mkdir(parents=True, exist_ok=True)
    manifest = []
    for item in diagrams().values():
        (sources / f"{item['id']}.mmd").write_text(item["source"])
        manifest.append({key: value for key, value in item.items() if key != "source"})
    (ARTIFACTS / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )
    rows = [
        "# Diagram Gallery",
        "",
        "[Mục lục tài liệu](../README.md). SVG được render từ Mermaid trong tài liệu gốc.",
        "",
        "Chạy `make docs-render` để cập nhật; file này được tạo tự động.",
        "",
        "| Sơ đồ | Tài liệu | SVG | Mermaid source |",
        "|---|---|---|---|",
    ]
    for item in manifest:
        identity = item["id"]
        rows.append(
            f"| {item['heading']} | [{item['document']}](../{item['document']}) "
            f"| [Xem SVG]({identity}.svg) | [Source](sources/{identity}.mmd) |"
        )
    (ARTIFACTS / "README.md").write_text("\n".join(rows) + "\n")
    print(f"Extracted {len(manifest)} Mermaid diagrams.")


def seal():
    """Record artifacts only after the render command has succeeded for all diagrams."""
    manifest_path = ARTIFACTS / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    current = diagrams()
    for item in manifest:
        if item["source_sha256"] != current[item["id"]]["source_sha256"]:
            raise ValueError("Markdown changed during rendering; render again")
        artifact = ARTIFACTS / f"{item['id']}.svg"
        tree = ElementTree.parse(artifact)
        if tree.getroot().tag != "{http://www.w3.org/2000/svg}svg":
            raise ValueError(f"Not an SVG: {artifact}")
        item["svg_sha256"] = sha(artifact.read_bytes())
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Recorded {len(manifest)} rendered SVG artifacts.")


def heading_ids(document):
    content = re.sub(r"```.*?```", "", document.read_text(), flags=re.DOTALL)
    result, counts = set(), {}
    for title in re.findall(r"^#{1,6}\s+(.+)$", content, re.MULTILINE):
        identity = re.sub(r"[^\w\- ]", "", title.strip().lower()).replace(" ", "-")
        occurrence = counts.get(identity, 0)
        counts[identity] = occurrence + 1
        result.add(identity if occurrence == 0 else f"{identity}-{occurrence}")
    return result


def check():
    errors, links = [], 0
    pages = [ROOT / "README.md", *DOCS.rglob("*.md"), *ROOT.glob("services/*/README.md")]
    for page in pages:
        content = re.sub(r"```.*?```", "", page.read_text(), flags=re.DOTALL)
        for raw in LINK.findall(content):
            target = urlsplit(raw.strip("<>"))
            if target.scheme or target.netloc:
                continue
            path = (page.parent / unquote(target.path)).resolve() if target.path else page
            links += 1
            if not path.exists():
                errors.append(f"{page.relative_to(ROOT)}: missing {raw}")
            elif target.fragment and path.suffix == ".md":
                if unquote(target.fragment) not in heading_ids(path):
                    errors.append(f"{page.relative_to(ROOT)}: missing anchor {raw}")
    current = diagrams()
    manifest_path = ARTIFACTS / "manifest.json"
    if not manifest_path.exists():
        errors.append("Missing manifest; run make docs-render")
        recorded = {}
    else:
        recorded = {item["id"]: item for item in json.loads(manifest_path.read_text())}
        if set(recorded) != set(current):
            errors.append("Diagram inventory changed; run make docs-render")
    for identity, item in current.items():
        entry = recorded.get(identity, {})
        source = ARTIFACTS / "sources" / f"{identity}.mmd"
        svg = ARTIFACTS / f"{identity}.svg"
        if not source.exists() or source.read_text() != item["source"]:
            errors.append(f"Stale or missing source: {identity}")
        if entry.get("source_sha256") != item["source_sha256"]:
            errors.append(f"Source digest mismatch: {identity}")
        if not svg.exists() or entry.get("svg_sha256") != sha(svg.read_bytes()):
            errors.append(f"Stale or missing SVG: {identity}")
        elif ElementTree.parse(svg).getroot().tag != "{http://www.w3.org/2000/svg}svg":
            errors.append(f"Invalid SVG root: {identity}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"OK: {len(pages)} Markdown files, {links} local links, {len(current)} Mermaid/SVG pairs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["extract", "seal", "check"])
    {"extract": extract, "seal": seal, "check": check}[parser.parse_args().command]()
