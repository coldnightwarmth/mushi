'use strict';
(() => {
const data=window.MUSHI_ANIMATIONS,root=document.getElementById('sequences');
function element(tag,text,className){const e=document.createElement(tag);if(text)e.textContent=text;if(className)e.className=className;return e;}
for(const sequence of data.sequences){
  const card=element('article',null,'sequence'),top=element('div',null,'sequence-top'),canvas=element('canvas');canvas.width=canvas.height=192;canvas.setAttribute('aria-label',sequence.label+' preview');
  const content=element('div'),title=element('h3',sequence.label),description=element('p','Primary layer · variants '+sequence.variants.join(', ')+' · 8 frames · plays once'),controls=element('div',null,'sequence-controls');
  const play=element('button','Play'),step=element('button','Next frame'),label=element('label','Preview speed '),speed=element('select');speed.setAttribute('aria-label',sequence.label+' preview speed');
  for(const n of [4,15,60]){const option=element('option',n+' fps');option.value=n;speed.append(option);}label.append(speed);
  const status=element('span','Loading frames…','sequence-status');status.setAttribute('aria-live','polite');controls.append(play,step,label,status);play.disabled=step.disabled=true;
  const links=element('div',null,'sequence-links'),metadata=element('a','Sequence metadata ↗');metadata.href=sequence.metadata;links.append(metadata);
  const strip=element('div',null,'frame-strip'),images=[],cells=[];
  for(const frame of sequence.frames){const link=element('a');link.href=frame.metadata;link.title='Inspect '+frame.id;const image=element('img');image.src=frame.source;image.alt=frame.id;link.append(image,element('span',frame.id));strip.append(link);images.push(image);cells.push(link);}
  content.append(title,description,controls,links);top.append(canvas,content);card.append(top,strip);root.append(card);
  const context=canvas.getContext('2d');context.imageSmoothingEnabled=false;
  let index=0,playing=false,next=0,request=0;
  function draw(){const image=images[index],scale=Math.max(1,Math.floor(160/Math.max(...sequence.frames.flatMap(f=>[f.width,f.height]))));context.clearRect(0,0,192,192);context.drawImage(image,(192-image.naturalWidth*scale)/2,(192-image.naturalHeight*scale)/2,image.naturalWidth*scale,image.naturalHeight*scale);status.textContent='Frame '+(index+1)+' / 8';cells.forEach((cell,i)=>cell.classList.toggle('current',i===index));}
  function stop(){playing=false;cancelAnimationFrame(request);play.textContent=index===7?'Replay':'Play';}
  function tick(time){if(!playing)return;if(time>=next){if(index===7){stop();return;}index++;draw();next=time+1000/Number(speed.value);}request=requestAnimationFrame(tick);}
  play.addEventListener('click',()=>{if(playing){stop();return;}index=0;draw();playing=true;play.textContent='Pause';next=performance.now()+1000/Number(speed.value);request=requestAnimationFrame(tick);});
  step.addEventListener('click',()=>{stop();index=(index+1)%8;draw();play.textContent=index===7?'Replay':'Play';});
  Promise.all(images.map(image=>image.decode())).then(()=>{draw();play.disabled=step.disabled=false;}).catch(()=>{status.textContent='Frame images could not load';});
}
})();
