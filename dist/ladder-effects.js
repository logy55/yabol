import anime from './anime.js?v=20261010-member-fixes';
export function animateLadderBoard(holder,elapsed,slotMs,traceMs){
  const animations=[],reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
  for(const path of holder.querySelectorAll('[data-ladder-path]')){
    const column=Number(path.dataset.ladderPath),ball=holder.querySelector(`[data-ladder-ball="${column}"]`),length=path.getTotalLength();
    const update=progress=>{const point=path.getPointAtLength(length*progress);path.style.strokeDashoffset=String(1-progress);ball.setAttribute('transform',`translate(${point.x} ${point.y}) rotate(${progress*1080})`);ball.style.opacity=elapsed>=column*slotMs&&progress<1?'1':'0';};
    if(elapsed>=column*slotMs+traceMs){update(1);continue;}
    const state={progress:0};
    const animation=anime({targets:state,progress:1,duration:traceMs,delay:column*slotMs,easing:'linear',autoplay:false,update:()=>{const active=animation.currentTime>=column*slotMs;update(state.progress);ball.style.opacity=!reduced&&active&&state.progress<1?'1':'0';}});
    animation.seek(Math.max(0,elapsed));animation.play();animations.push(animation);
  }
  return()=>animations.forEach(animation=>animation.pause());
}
export function revealLadderResult(holder,column,end,label,celebrate){
  const card=holder.querySelector(`[data-result="${column}"]`);if(!card.hidden)return;
  card.hidden=false;card.dataset.outcome=label==='꽝'?'lose':'pass';
  const text=holder.querySelector(`[data-slot="${end}"]`),chip=holder.querySelector(`[data-slot-chip="${end}"]`);
  text.textContent=label;chip.dataset.outcome=card.dataset.outcome;text.dataset.outcome=card.dataset.outcome;
  if(!celebrate||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  anime({targets:card,translateY:[14,0],opacity:[0,1],duration:480,easing:'easeOutBack'});
  if(label==='꽝')anime({targets:card,translateX:[0,-6,6,-4,4,0],duration:600,easing:'easeInOutSine'});
  else{const burst=document.createElement('div');burst.className='ladder-confetti';burst.setAttribute('aria-hidden','true');for(let i=0;i<18;i++){const bit=document.createElement('i');bit.style.setProperty('--bit-colour',['#6a9bcc','#dcae58','#78ac96','#a793c6'][i%4]);burst.append(bit);}card.append(burst);anime({targets:burst.children,translateX:(_,i)=>Math.cos(i*2.4)*80,translateY:(_,i)=>-30-Math.sin(i*1.7)*55,rotate:(_,i)=>i*80,opacity:[1,0],duration:1000,easing:'easeOutCubic',complete:()=>burst.remove()});}
}
