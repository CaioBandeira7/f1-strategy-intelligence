// ---- assemble + PUT ----
const T=window.__n, OUT=window.__OUT, CSS=window.__CSS.slice();
const C={bg:'#0B0F17',panel:'#151C29',border:'#2B3545'};
for(const v of OUT.ve){ if(['Graph','Table','Prompt'].includes(v['@element'])) CSS.push(['#'+v.name+' .Container',{'background-color':C.panel,'border-width':'1px','border-color':C.border,'border-style':'solid',transparency:'0'}]); }
CSS.unshift(['.Report',{'background-color':C.bg}],['.ReportElementContainer',{padding:'6px'}]);
const styles={}; let cdata='';
for(const [sel,props] of CSS){ styles[sel]={'@element':'Style',styleName:sel,properties:Object.assign({},(styles[sel]||{}).properties,props)}; }
for(const [sel,st] of Object.entries(styles)){ cdata+=sel+' {\n'+Object.entries(st.properties).map(([k,v])=>'  '+k+' : '+v+';').join('\n')+'\n}\n'; }
const P=window.__PAGES; const order=[0,1,2,3,6,4,5];
const rep=JSON.parse(JSON.stringify(T));
rep.label='F1 Strategy Intelligence | 2023–2025';
rep.dataSources=window.__dsList; rep.dataDefinitions=OUT.dd; rep.visualElements=OUT.ve; rep.interactions=OUT.ia;
rep.view.sections=order.map(i=>P[i]);
rep.mediaSchemes[0].baseStylesheetResource.theme='dark2025';
rep.mediaSchemes[0].stylesheet={'@element':'Stylesheet',cdata,styles};
rep.properties=[{'@element':'Property',key:'displayDataSource',value:window.__dsList[0].name}];
rep.nextUniqueNameIndex=window.__IDX+50;
delete rep.history; delete rep.sasReportState;
window.__rep=rep;
const id=window.__rid; const H={Accept:'application/vnd.sas.report.content+json'};
const g=await fetch('/reports/reports/'+id+'/content',{headers:H}); const etag=g.headers.get('ETag');
window.__backup=await g.text();
const r=await fetch('/reports/reports/'+id+'/content',{method:'PUT',headers:{'Content-Type':'application/vnd.sas.report.content+json','If-Match':etag,Accept:'application/vnd.sas.report.content+json'},body:JSON.stringify(rep)});
r.status+' '+(await r.text()).slice(0,800)
