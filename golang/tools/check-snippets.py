#!/usr/bin/env python3
"""Compile Go Markdown examples in isolated, compile-only harnesses."""
from pathlib import Path
import os,re,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'.cache/snippets';OUT.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['GOCACHE']=str(ROOT/'.cache/go-build');env['GOMODCACHE']=str(ROOT/'.cache/go-mod')
imports={'fmt':'fmt','errors':'errors','context':'context','time':'time','sync':'sync','io':'io','sql':'database/sql'}
results=[]
for p in sorted(ROOT.rglob('*.md')):
 if '.cache' in p.parts:continue
 for index,code in enumerate(re.findall(r'```go\s*\n(.*?)```',p.read_text(),re.S),1):
  kind='complete program'
  if not re.match(r'\s*package\s+',code):
   kind='documented snippet with imports supplied'
   if code.lstrip().startswith('func '):body=code
   elif 'db.SetMax' in code:
    body='func Demo(db *sql.DB) {\n'+code+'\n}'
   else:body='func Demo() {\n'+code+'\n}'
   used=[v for k,v in imports.items() if re.search(r'\b'+k+r'\.',body)]
   code='package snippet\n'+('import (\n'+''.join('"'+x+'"\n' for x in used)+')\n' if used else '')+body
  path=OUT/f'example_{len(results)+1:03}.go';path.write_text(code)
  result=subprocess.run(['go','test',str(path)],cwd=ROOT/'examples',env=env,text=True,capture_output=True)
  results.append({'file':str(p.relative_to(ROOT)),'block':index,'kind':kind,'passed':result.returncode==0,'error':result.stderr+result.stdout if result.returncode else ''})
report={'checked':len(results),'failed':[x for x in results if not x['passed']],'results':results}
(ROOT/'.cache/snippets-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'checked':report['checked'],'failed':report['failed']},ensure_ascii=False,indent=2));sys.exit(bool(report['failed']))
