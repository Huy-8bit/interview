"""Kiểm tra cấu trúc của bộ tài liệu Python Backend.

Chạy: python knowledges/scripts/validate.py [--strict]

Các kiểm tra:
- Link Markdown nội bộ trỏ tới file tồn tại.
- Không còn cấu trúc hỏi đáp kiểu phỏng vấn (Interview Questions, Quiz, B1/L1...).
- Không có placeholder (TODO, TBD, FIXME).
- Code block Python parse được bằng `ast`.
- Mermaid block có kiểu diagram hợp lệ và có đoạn giải thích ngay sau.
- Bài system design có đủ các phần bắt buộc và tối thiểu 5 diagram.
- Module README có các phần định hướng.
- Cảnh báo đoạn văn tiếng Anh dài (heuristic) với --strict.

Script chỉ kiểm tra cấu trúc. Cú pháp Mermaid chi tiết nên được kiểm tra
thêm bằng trình parse của Mermaid (ví dụ mermaid-cli) khi có Node.js.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import re
import sys
from pathlib import Path

KNOWLEDGE_ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = KNOWLEDGE_ROOT.parent

BANNED_PATTERNS = [
    r"^#+ .*Interview Questions",
    r"^#+ .*Senior-level Questions",
    r"^#+ .*Follow-up Questions",
    r"^#+ .*What interviewer may ask",
    r"^#+ .*Check Your Understanding",
    r"^#+ .*\bQuiz\b",
    r"^#+ .*Practice Questions",
    r"^#+ .*Mock Interview",
    r"^#+ .*Short Answers?\b",
    r"^#+ .*How to explain this design in an interview",
    r"\*\*[BLSF]\d+\.\*\*",
]
PLACEHOLDER = re.compile(r"\b(?:TODO|TBD|FIXME|XXX)\b")
MERMAID_TYPES = re.compile(
    r"^(?:flowchart|graph|sequenceDiagram|stateDiagram(?:-v2)?|erDiagram|"
    r"classDiagram|gantt|timeline|journey|pie|quadrantChart|mindmap)\b"
)
DESIGN_SECTIONS = [
    "Bài toán", "Yêu cầu chức năng", "Yêu cầu phi chức năng", "Ước lượng tải",
    "API", "Data Model", "Architecture ban đầu", "Architecture mở rộng",
    "Request Flow", "Data Flow", "Storage", "Database", "Cache", "Queue",
    "Scaling", "Failure Modes", "Recovery", "Security", "Observability",
    "Trade-offs", "Architecture Evolution", "Tóm tắt",
]
README_SECTIONS = [
    "Module này học gì?", "Tại sao cần học?", "Thứ tự nên đọc",
    "Các concept phụ thuộc nhau thế nào?", "File quan trọng nhất",
]
VIETNAMESE_CHARS = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]",
    re.IGNORECASE,
)


def strip_code(text: str) -> str:
    return re.sub(r"```.*?```", "", text, flags=re.S)


def check_links(path: Path, text: str, errors: list[str], rel: Path) -> int:
    count = 0
    for target in re.findall(r"(?<!!)\[[^\]]+\]\(([^)\s]+)\)", strip_code(text)):
        target = target.split("#", 1)[0]
        if not target or re.match(r"^(?:https?://|mailto:)", target):
            continue
        count += 1
        if not (path.parent / target).resolve().exists():
            errors.append(f"Broken link in {rel}: {target}")
    return count


def check_mermaid(text: str, errors: list[str], rel: Path) -> int:
    blocks = list(re.finditer(r"```mermaid\n(.*?)\n```", text, flags=re.S))
    for number, match in enumerate(blocks, 1):
        body = match.group(1)
        first = next((ln.strip() for ln in body.splitlines() if ln.strip()), "")
        if not MERMAID_TYPES.match(first):
            errors.append(f"Unknown Mermaid type #{number} in {rel}: {first}")
        if re.search(r"(?m)^\s*end\s*-->|-->\s*end\s*$", body):
            errors.append(f"Mermaid #{number} in {rel} uses reserved node id 'end'")
        after = text[match.end():].lstrip("\n")
        next_line = after.splitlines()[0].strip() if after else ""
        if not next_line or next_line.startswith("#") or next_line.startswith("```"):
            errors.append(f"Mermaid #{number} in {rel} has no explanation right after it")
    return len(blocks)


def check_python(text: str, errors: list[str], rel: Path) -> int:
    blocks = re.findall(r"```python\n(.*?)\n```", text, flags=re.S)
    for number, code in enumerate(blocks, 1):
        try:
            ast.parse(code)
        except SyntaxError as exc:
            errors.append(f"Invalid Python block #{number} in {rel}: {exc.msg} (line {exc.lineno})")
    return len(blocks)


def english_paragraphs(text: str) -> list[str]:
    found = []
    for para in re.split(r"\n\s*\n", strip_code(text)):
        para = para.strip()
        if not para or para.startswith(("|", "#", ">", "-", "*", "[", "1.")):
            continue
        words = re.findall(r"[A-Za-zÀ-ỹ]+", para)
        if len(words) >= 25 and not VIETNAMESE_CHARS.search(para):
            found.append(para[:80])
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="coi cảnh báo là lỗi")
    args = parser.parse_args()

    files = sorted(KNOWLEDGE_ROOT.rglob("*.md"))
    main_readme = PYTHON_ROOT / "README.md"
    if main_readme.exists():
        files.insert(0, main_readme)

    errors: list[str] = []
    warnings: list[str] = []
    hashes: dict[str, list[Path]] = {}
    totals = {"links": 0, "mermaid": 0, "python": 0}

    for path in files:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(PYTHON_ROOT)
        hashes.setdefault(hashlib.sha256(text.encode()).hexdigest(), []).append(rel)

        if not text.strip():
            errors.append(f"Empty file: {rel}")
            continue
        prose = strip_code(text)
        for pattern in BANNED_PATTERNS:
            if re.search(pattern, prose, flags=re.M | re.I):
                errors.append(f"Interview-style structure in {rel}: /{pattern}/")
        if PLACEHOLDER.search(prose):
            errors.append(f"Placeholder marker in {rel}")

        totals["links"] += check_links(path, text, errors, rel)
        totals["mermaid"] += check_mermaid(text, errors, rel)
        totals["python"] += check_python(text, errors, rel)

        is_module_readme = path.name == "README.md" and path.parent.parent == KNOWLEDGE_ROOT
        if is_module_readme and path.parent.name not in {"22-references"}:
            missing = [s for s in README_SECTIONS if f"## {s}" not in text]
            if missing:
                errors.append(f"README {rel} missing: {', '.join(missing)}")
        elif path.name != "README.md" and path != main_readme:
            if "## Liên quan" not in text:
                warnings.append(f"No 'Liên quan' section: {rel}")

        for snippet in english_paragraphs(text):
            warnings.append(f"Long English paragraph in {rel}: {snippet}...")

    for path in sorted((KNOWLEDGE_ROOT / "11-system-design").glob("design-*.md")):
        text = path.read_text(encoding="utf-8")
        headings = "\n".join(re.findall(r"(?m)^##+ .*$", text))
        missing = [s for s in DESIGN_SECTIONS if s not in headings]
        if missing:
            errors.append(f"System design {path.name} missing sections: {', '.join(missing)}")
        if text.count("```mermaid") < 5:
            errors.append(f"System design {path.name} has fewer than 5 diagrams")
        if "sequenceDiagram" not in text:
            errors.append(f"System design {path.name} has no sequence diagram")

    for duplicates in hashes.values():
        if len(duplicates) > 1:
            errors.append("Duplicate files: " + ", ".join(map(str, duplicates)))

    for warning in warnings:
        print(f"WARN  {warning}")
    for error in errors:
        print(f"ERROR {error}")
    print(
        f"\nFiles: {len(files)} · local links: {totals['links']} · "
        f"mermaid blocks: {totals['mermaid']} · python blocks: {totals['python']}"
    )
    print(f"Errors: {len(errors)} · Warnings: {len(warnings)}")
    failed = bool(errors) or (args.strict and bool(warnings))
    print("VALIDATION FAILED" if failed else "VALIDATION PASSED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
