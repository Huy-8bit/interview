// Usage: node tools/check-mermaid.mjs /path/to/node_modules
// Needs mermaid and puppeteer installed in the supplied directory.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const modules=process.argv[2];
if(!modules) throw new Error('Pass a node_modules directory containing mermaid and puppeteer');
const require=createRequire(path.resolve(modules,'../package.json'));
const puppeteer=require(path.resolve(modules,'puppeteer'));
const input=JSON.parse(fs.readFileSync(path.join(root,'.cache/diagrams.json'),'utf8'));
const browser=await puppeteer.launch({headless:true,args:['--no-sandbox','--disable-setuid-sandbox']});
const errors=[];
try {
 const page=await browser.newPage();
 await page.setContent('<!doctype html><html><body></body></html>');
 await page.addScriptTag({path:path.resolve(modules,'mermaid/dist/mermaid.min.js')});
 await page.evaluate(()=>mermaid.initialize({startOnLoad:false,securityLevel:'strict'}));
 for(const item of input){
  const failure=await page.evaluate(async code=>{try{await mermaid.parse(code);return null}catch(e){return String(e)}},item.code);
  if(failure)errors.push({file:item.file,index:item.index,error:failure});
 }
 const version=JSON.parse(fs.readFileSync(path.resolve(modules,'mermaid/package.json'),'utf8')).version;
 const report={version,checked:input.length,errors};
 fs.writeFileSync(path.join(root,'.cache/mermaid-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}finally{await browser.close();}
process.exitCode=errors.length?1:0;
