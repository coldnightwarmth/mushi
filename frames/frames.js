'use strict';
(() => {
const data=window.MUSHI_FRAMES, $=id=>document.getElementById(id), pageSize=96;
const frameID=i=>'frame-'+String(i).padStart(5,'0'), resourceID=i=>'u2-'+String(i).padStart(4,'0');
const records=data.rows.map((r,index)=>({index,id:frameID(index),resource:r[0],x:r[1],y:r[2],w:r[3],h:r[4],duplicate:r[5],opaque:r[6]}));
let page=0, filtered=records;
for (const [number,label] of [[data.coverage.frame_entries,'frame entries'],[data.coverage.source_resources,'source sheets']]) {
  const stat=document.createElement('div');stat.className='stat';
  const strong=document.createElement('strong'),span=document.createElement('span');
  strong.textContent=number.toLocaleString();span.textContent=label;stat.append(strong,span);$('stats').append(stat);
}
function show(r) {
  $('detail-title').textContent=r.id;$('detail-image').src='images/'+r.id+'.png';$('detail-image').alt=r.id+' upright frame';
  const entries=[['Source resource',resourceID(r.resource)],['Upright size',r.w+' × '+r.h],['Upright rectangle',[r.x,r.y,r.w,r.h].join(', ')],['Board source rectangle',[256-r.y-r.h,r.x,r.h,r.w].join(', ')],['Program address','0x'+(0x0c20bf14+r.index*10).toString(16)],['Visible pixels',r.opaque.toLocaleString()],['Pixel duplicate',r.duplicate===null?'First matching image':frameID(r.duplicate)]];
  $('properties').replaceChildren();for (const [key,value] of entries) {const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=key;dd.textContent=value;$('properties').append(dt,dd);}
  $('download').href='images/'+r.id+'.png';$('download').download=r.id+'.png';$('metadata').href='metadata/'+r.id+'.json';$('sheet').href='../sheets/'+resourceID(r.resource)+'.png';
  $('detail').showModal();
}
function draw() {
  const pages=Math.max(1,Math.ceil(filtered.length/pageSize));page=Math.min(page,pages-1);
  $('grid').replaceChildren();
  for (const r of filtered.slice(page*pageSize,(page+1)*pageSize)) {
    const card=document.createElement('button');card.className='card';card.setAttribute('aria-label','Inspect '+r.id);
    const art=document.createElement('div');art.className='art';const img=document.createElement('img');img.src='images/'+r.id+'.png';img.alt='';img.loading='lazy';art.append(img);
    const caption=document.createElement('div');caption.className='caption';const title=document.createElement('strong'),detail=document.createElement('small');title.textContent=r.id;detail.textContent=resourceID(r.resource)+' · '+r.w+' × '+r.h;caption.append(title,detail);card.append(art,caption);card.addEventListener('click',()=>show(r));$('grid').append(card);
  }
  $('count').textContent=filtered.length.toLocaleString()+' '+(filtered.length===1?'frame entry':'frame entries');$('page').textContent=(page+1)+' / '+pages;$('prev').disabled=page===0;$('next').disabled=page===pages-1;
}
function filter() {
  const words=$('search').value.toLowerCase().trim().split(/\s+/).filter(Boolean), kind=$('filter').value,size=$('size').value;
  filtered=records.filter(r=>{
    if(kind==='unique'&&r.duplicate!==null||kind==='duplicates'&&r.duplicate===null||kind==='empty'&&r.opaque!==0)return false;
    const max=Math.max(r.w,r.h);if(size==='small'&&max>16||size==='medium'&&(max<=16||max>64)||size==='large'&&max<=64)return false;
    const text=[r.id,resourceID(r.resource),r.w+'x'+r.h,r.w+'×'+r.h].join(' ');return words.every(word=>text.includes(word));
  });page=0;draw();
}
$('search').addEventListener('input',filter);$('filter').addEventListener('change',filter);$('size').addEventListener('change',filter);
$('prev').addEventListener('click',()=>{page--;draw();});$('next').addEventListener('click',()=>{page++;draw();});$('close').addEventListener('click',()=>$('detail').close());
$('detail').addEventListener('click',event=>{if(event.target===$('detail')){const r=$('detail').getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)$('detail').close();}});
draw();
})();
