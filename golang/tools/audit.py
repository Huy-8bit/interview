#!/usr/bin/env python3
"""Audit source content without editing it; reports are written inside golang/.cache."""
from pathlib import Path
from collections import defaultdict
import hashlib,json,re,sys,unicodedata
ROOT=Path(__file__).resolve().parents[1]
CAT=json.loads((ROOT/'tools/catalog.json').read_text())
required=json.loads((ROOT/'tools/required-files.json').read_text())
errors=[];warnings=[];diagrams=[];hashes=defaultdict(list);questions=set();question_occurrences=0
files=sorted(ROOT.rglob('*.md'))
files=[p for p in files if '.cache' not in p.parts]
def plain(text):return re.sub(r'```.*?```','',text,flags=re.S)
def slug(text):
 text=re.sub(r'[`*_]','',text.strip().lower());text=re.sub(r'[^\w\- ]','',text,flags=re.UNICODE);return text.replace(' ','-')
for f in required:
 if not(ROOT/f).is_file():errors.append(f'missing required file: {f}')
for p in files:
 rel=str(p.relative_to(ROOT));s=p.read_text();body=plain(s)
 if len(re.findall(r'^```',s,re.M))%2:errors.append(f'{rel}: unbalanced code fences')
 if not s.startswith('# '):errors.append(f'{rel}: missing title')
 if re.search(r'\b(?:TBD|FIXME|PLACEHOLDER)\b|\[insert .+?\]',body,re.I):errors.append(f'{rel}: unfinished marker')
 # Context.TODO is a real Go API. Bare task markers are not accepted.
 if re.search(r'(?<![.\w])TODO\s*:',body):errors.append(f'{rel}: TODO task marker')
 for i,d in enumerate(re.findall(r'```mermaid\s*\n(.*?)```',s,re.S),1):diagrams.append({'file':rel,'index':i,'code':d.strip()})
 for label,target in re.findall(r'\[([^\]]*)\]\(([^)]+)\)',body):
  if re.match(r'^[a-z]+:',target):continue
  target=target.split(' "')[0].strip('<>');name,_,anchor=target.partition('#')
  dest=(p.parent/name).resolve() if name else p
  if not dest.exists():errors.append(f'{rel}: broken link {target}')
  elif anchor and dest.suffix=='.md':
   headings=[slug(x) for x in re.findall(r'^#+\s+(.+)$',dest.read_text(),re.M)]
   if anchor not in headings:errors.append(f'{rel}: missing anchor {target}')
 for q in re.findall(r'([^\n?]+\?)',body):
  q=re.sub(r'^[#\d. *-]+','',q).strip('* ')
  if len(q.split())>=4:questions.add(q);question_occurrences+=1
 hashes[hashlib.sha256(s.encode()).hexdigest()].append(rel)
 words=len(body.split())
 if CAT.get(rel,{}).get('priority')=='P0':
  for term in ['Concept','Mental Model','Why','How','Internals','Code Example','Production Use Case','Failure Scenarios','Trade-offs','Common Misconceptions','When NOT to use','How I would debug this in production','Interview Questions','Senior Follow-ups','Key Takeaways']:
   if term not in s:errors.append(f'{rel}: missing P0 section {term}')
  if not re.search(r'```mermaid',s):errors.append(f'{rel}: P0 diagram absent')
  for heading,count in [('Basic / Mid — 10',10),('Senior — 10',10),('Production scenarios — 5',5),('Senior Follow-ups — 5',5)]:
   match=re.search(r'^### '+re.escape(heading)+r'\n(.*?)(?=^##|\Z)',s,re.M|re.S)
   actual=len(re.findall(r'^\d+\. .+\?',match.group(1),re.M)) if match else 0
   if actual!=count:errors.append(f'{rel}: {heading} has {actual}')
  if words<650:errors.append(f'{rel}: P0 review depth only {words} words')
 elif re.match(r'\d\d-',p.parent.name) and p.name!='README.md' and not p.parent.name.startswith(('00-','23-','24-')) and words<180:
  warnings.append(f'{rel}: review depth {words} words')
 if p.name.startswith('design-') and p.parent.name=='13-system-design':
  if s.count('```mermaid')<5:errors.append(f'{rel}: design has fewer than5 diagrams')
  for h in ['Requirements','Non-functional Requirements','Capacity Estimation','API','Data Model','High-Level Architecture','Request Flow','Data Flow','Scaling','Failure Modes','Observability','Security','Trade-offs','Evolution','Go Service Implementation']:
   if f'## {h}' not in s:errors.append(f'{rel}: missing design section {h}')
for names in hashes.values():
 if len(names)>1:errors.append('duplicate full documents: '+', '.join(names))
for name,count in [('top-100-golang-questions.md',100),('top-50-senior-backend-questions.md',50)]:
 s=(ROOT/'23-mock-interview'/name).read_text();numbers=[int(x) for x in re.findall(r'^### (\d+)\.',s,re.M)]
 if numbers!=list(range(1,count+1)):errors.append(f'{name}: expected consecutive1..{count}')
 if s.count('<details>')!=count or s.count('</details>')!=count:errors.append(f'{name}: answer sections incomplete')
baseline=json.loads((ROOT/'tools/python-baseline.json').read_text())
now={str(p.relative_to(ROOT.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT.parent/'python').rglob('*') if p.is_file()}
drift={'removed':sorted(baseline.keys()-now.keys()),'added':sorted(now.keys()-baseline.keys()),'modified':sorted(k for k in baseline.keys()&now.keys() if baseline[k]!=now[k])}
if now!=baseline:warnings.append('Python changed outside this task during execution; no Python writes were performed by this task. See python_drift counts.')
# Detect verbatim paragraph copying from Python without modifying any source.
python_paragraphs=set()
for name in now:
 p=ROOT.parent/name
 if p.suffix=='.md':
  for paragraph in re.split(r'\n\s*\n',plain(p.read_text())):
   paragraph=' '.join(paragraph.split())
   if len(paragraph)>250:python_paragraphs.add(paragraph)
for p in files:
 for paragraph in re.split(r'\n\s*\n',plain(p.read_text())):
  if ' '.join(paragraph.split()) in python_paragraphs:errors.append(f'{p.relative_to(ROOT)}: long paragraph identical to Python')
report={'markdown_files':len(files),'required_files':len(required),'p0_articles':sum(v.get('priority')=='P0' for v in CAT.values()),'mermaid_diagrams':len(diagrams),'system_designs':len(list((ROOT/'13-system-design').glob('design-*.md'))),'production_scenarios':len([p for p in (ROOT/'20-production-scenarios').glob('*.md') if p.name!='README.md']),'interview_question_occurrences':question_occurrences,'distinct_question_texts':len(questions),'python_baseline_matches':now==baseline,'python_baseline_files':len(baseline),'python_current_files':len(now),'python_drift':{k:len(v) for k,v in drift.items()},'errors':errors,'warnings':warnings}
(ROOT/'.cache').mkdir(exist_ok=True)
(ROOT/'.cache/audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
(ROOT/'.cache/diagrams.json').write_text(json.dumps(diagrams,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2));sys.exit(bool(errors))
