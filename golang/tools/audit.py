#!/usr/bin/env python3
"""Check lesson structure and links; semantic correctness still requires review."""
from pathlib import Path
from collections import defaultdict
import argparse
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CAT = json.loads((ROOT / 'tools/catalog.json').read_text())
REQUIRED = json.loads((ROOT / 'tools/required-files.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--python-baseline', type=Path, default=ROOT / 'tools/python-baseline.json')
args = parser.parse_args()
errors, warnings, diagrams, inventory = [], [], [], []
hashes = defaultdict(list)
files = sorted(p for p in ROOT.rglob('*.md') if '.cache' not in p.parts)
FENCE = re.compile(r'^```([^\n]*)\n(.*?)^```[ \t]*$', re.M | re.S)
FORBIDDEN = re.compile(r'^#{2,6}\s+.*(?:Interview\s+(?:Practice|Questions|rehearsal)|Senior\s+(?:Questions|Follow-ups)|Follow-ups|Check Your Understanding)', re.M | re.I)

def plain(text):
    return FENCE.sub('', text)

def slug(text):
    text = re.sub(r'[`*_]', '', text.strip().lower())
    return re.sub(r'[^\w\- ]', '', text).replace(' ', '-')

def kind(path):
    parent = path.parent.name
    if path.name == 'README.md' or parent == '00-roadmap':
        return 'guide'
    if parent == '23-mock-interview':
        return 'practice_appendix'
    if parent == '24-cheatsheets' or path.name == 'references.md':
        return 'reference_appendix'
    if re.match(r'(?:0[1-9]|1\d|2[012])-', parent):
        return 'lesson'
    return 'tooling'

for rel in REQUIRED:
    if not (ROOT / rel).is_file():
        errors.append(f'missing required file: {rel}')

for path in files:
    rel = str(path.relative_to(ROOT))
    text = path.read_text()
    body = plain(text)
    article_kind = kind(path)
    word_count = len(body.split())
    priority = CAT.get(rel, {}).get('priority')
    blocks = list(FENCE.finditer(text))
    diagram_count = sum(m[1].strip() == 'mermaid' for m in blocks)
    code_count = sum(m[1].strip() not in ('mermaid', 'text', '') for m in blocks)
    inventory.append({'file': rel, 'kind': article_kind, 'priority': priority,
                      'prose_words': word_count, 'diagrams': diagram_count,
                      'code_blocks': code_count})
    hashes[hashlib.sha256(text.encode()).hexdigest()].append(rel)
    if not text.startswith('# '):
        errors.append(f'{rel}: missing title')
    if len(re.findall(r'^```', text, re.M)) != 2 * len(blocks):
        errors.append(f'{rel}: malformed or unbalanced fences')
    if re.search(r'\b(?:TBD|FIXME|PLACEHOLDER)\b|\[insert .+?\]', body):
        errors.append(f'{rel}: unfinished marker')
    if re.search(r'(?<![.\w])TODO\s*:', body):
        errors.append(f'{rel}: unfinished task marker')
    for match in blocks:
        language = match[1].strip()
        after = text[match.end():].lstrip()
        if language == 'mermaid':
            index = sum(d['file'] == rel for d in diagrams) + 1
            diagrams.append({'file': rel, 'index': index, 'code': match[2].strip()})
            if not after.startswith('### Cách đọc diagram\n'):
                errors.append(f'{rel}: diagram {index} lacks immediate reading guide')
            else:
                explanation = re.split(r'^#{1,6} ', after.split('\n', 1)[1], maxsplit=1, flags=re.M)[0]
                if len(explanation.split()) < 25:
                    errors.append(f'{rel}: diagram {index} explanation needs substantive review')
        elif language not in ('', 'text'):
            if not after.startswith('### Giải thích'):
                errors.append(f'{rel}: {language} block lacks immediate walkthrough')
            else:
                explanation = re.split(r'^#{1,6} ', after.split('\n', 1)[1], maxsplit=1, flags=re.M)[0]
                if len(explanation.split()) < 25:
                    errors.append(f'{rel}: {language} walkthrough too short to explain behavior')
    for _, target in re.findall(r'\[([^\]]*)\]\(([^)]+)\)', body):
        if re.match(r'^[a-z]+:', target):
            continue
        target = target.split(' "')[0].strip('<>')
        name, _, anchor = target.partition('#')
        dest = (path.parent / name).resolve() if name else path
        if not dest.exists():
            errors.append(f'{rel}: broken link {target}')
        elif anchor and dest.suffix == '.md':
            headings = [slug(x) for x in re.findall(r'^#+\s+(.+)$', dest.read_text(), re.M)]
            if anchor not in headings:
                errors.append(f'{rel}: missing anchor {target}')
    if article_kind == 'lesson':
        if FORBIDDEN.search(text):
            errors.append(f'{rel}: interview/question section in a theory lesson')
        if len(re.findall(r'^\s*(?:- \[[ x]\]|\d+\. .*\?)', body, re.M)) >= 5:
            errors.append(f'{rel}: theory is still structured as a question/checklist bank')
        if word_count < 300:
            errors.append(f'{rel}: insufficient standalone explanation ({word_count} words)')
        if not re.search(r'ví dụ|tình huống|bài toán', body, re.I):
            errors.append(f'{rel}: no problem/example entry point')
        if not re.search(r'production|thực tế|hệ thống|nghiệp vụ|request|worker|gateway', body, re.I):
            errors.append(f'{rel}: no application context')
        if priority == 'P0':
            if word_count < 900:
                errors.append(f'{rel}: foundational topic needs deeper teaching ({word_count} words)')
            if not diagram_count:
                errors.append(f'{rel}: foundational lesson lacks explanatory diagram')
            if not re.search(r'debug|bằng chứng|điều tra|profile|trace', body, re.I):
                errors.append(f'{rel}: foundational lesson lacks diagnostic reasoning')
            if not re.search(r'trade-off|đánh đổi|giới hạn', body, re.I):
                errors.append(f'{rel}: foundational lesson lacks trade-offs/limits')
        if path.name.startswith('design-') and path.parent.name == '13-system-design':
            if diagram_count < 5:
                errors.append(f'{rel}: design lacks architecture/request/data/scale/failure diagrams')
            for required in ['Phiên bản 1', 'Phiên bản 2', 'Phiên bản 3']:
                if required.lower() not in body.lower():
                    errors.append(f'{rel}: missing incremental explanation {required}')
            for heading in ['Requirements', 'Non-functional Requirements', 'Capacity Estimation',
                            'API', 'Data Model', 'High-Level Architecture', 'Request Flow', 'Data Flow',
                            'Scaling', 'Failure Modes', 'Observability', 'Security', 'Evolution',
                            'Go Service Implementation']:
                if '## ' + heading not in text:
                    errors.append(f'{rel}: missing design detail {heading}')
        if path.parent.name == '20-production-scenarios':
            for term in ['mô phỏng', 'giả thuyết']:
                if term not in body.lower():
                    warnings.append(f'{rel}: manually review scenario framing: {term}')

for names in hashes.values():
    if len(names) > 1:
        errors.append('duplicate full documents: ' + ', '.join(names))
for name, count in [('top-100-golang-questions.md', 100), ('top-50-senior-backend-questions.md', 50)]:
    text = (ROOT / '23-mock-interview' / name).read_text()
    numbers = [int(x) for x in re.findall(r'^### (\d+)\.', text, re.M)]
    if numbers != list(range(1, count + 1)) or text.count('<details>') != count or text.count('</details>') != count:
        errors.append(f'{name}: standalone practice appendix numbering/answers incomplete')

baseline = json.loads(args.python_baseline.read_text())
now = {str(p.relative_to(ROOT.parent)): hashlib.sha256(p.read_bytes()).hexdigest()
       for p in (ROOT.parent / 'python').rglob('*') if p.is_file()}
drift = {'removed': len(baseline.keys() - now.keys()), 'added': len(now.keys() - baseline.keys()),
         'modified': sum(baseline[k] != now[k] for k in baseline.keys() & now.keys())}
if now != baseline:
    warnings.append('Python differs from the selected read-only snapshot; this comparison does not attribute the edits. No restore is performed.')
python_paragraphs = set()
for rel in now:
    path = ROOT.parent / rel
    if path.suffix == '.md':
        for paragraph in re.split(r'\n\s*\n', plain(path.read_text())):
            paragraph = ' '.join(paragraph.split())
            if len(paragraph) > 250:
                python_paragraphs.add(paragraph)
for path in files:
    for paragraph in re.split(r'\n\s*\n', plain(path.read_text())):
        if ' '.join(paragraph.split()) in python_paragraphs:
            errors.append(f'{path.relative_to(ROOT)}: long paragraph identical to Python')

report = {'markdown_files': len(files), 'required_files': len(REQUIRED),
          'lessons': sum(x['kind'] == 'lesson' for x in inventory),
          'p0_articles': sum(x['priority'] == 'P0' for x in inventory),
          'mermaid_diagrams': len(diagrams), 'code_blocks': sum(x['code_blocks'] for x in inventory),
          'system_designs': len(list((ROOT / '13-system-design').glob('design-*.md'))),
          'production_scenarios': len(list((ROOT / '20-production-scenarios').glob('*.md'))) - 1,
          'python_baseline_matches': now == baseline, 'python_drift': drift,
          'errors': errors, 'warnings': warnings,
          'limits': 'Structure, word counts and explanation headings are review aids, not proof of technical accuracy or teaching quality.'}
(ROOT / '.cache').mkdir(exist_ok=True)
for name, value in [('audit.json', report), ('diagrams.json', diagrams), ('lesson-inventory.json', inventory)]:
    (ROOT / '.cache' / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(bool(errors))
