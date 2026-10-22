import {canManageMembers} from './admin-model.js?v=20261022-room-controls';

export function createPendingMemberAlert(element,getContext){
  let owner='',sequence=0,inFlight=null;
  const button=element.querySelector('[data-pending-toggle]'),popover=element.querySelector('[data-pending-popover]');
  function close(){if(popover)popover.hidden=true;button?.setAttribute('aria-expanded','false');}
  function position(){
    if(!popover||popover.hidden)return;
    const view=element.ownerDocument.defaultView,rect=button.getBoundingClientRect(),width=Math.min(280,view.innerWidth-24);
    Object.assign(popover.style,{width:`${width}px`,left:`${Math.min(view.innerWidth-width-12,Math.max(12,rect.right-width))}px`,top:`${rect.bottom+9}px`});
  }
  if(button&&popover){
    button.addEventListener('click',()=>{const open=popover.hidden;popover.hidden=!open;button.setAttribute('aria-expanded',String(open));position();});
    element.ownerDocument.addEventListener('click',event=>{if(!element.contains(event.target))close();});
    element.ownerDocument.addEventListener('keydown',event=>{if(event.key==='Escape'&&!popover.hidden){close();button.focus();}});
    popover.addEventListener('click',event=>{if(event.target.closest('a'))close();});
    element.ownerDocument.defaultView.addEventListener('resize',position);
    element.ownerDocument.defaultView.addEventListener('scroll',position,{passive:true});
  }
  function clear(){owner='';sequence++;inFlight=null;element.hidden=true;close();for(const label of element.querySelectorAll('[data-pending-count]'))label.textContent='';}
  function eligible(context){return Boolean(context.db&&context.userId&&canManageMembers(context.member));}
  async function refresh(){
    const context=getContext();
    if(!eligible(context)){clear();return;}
    const key=`${context.userId}:${context.epoch}`;
    if(owner!==key){clear();owner=key;}
    if(inFlight)return inFlight;
    const current=++sequence;
    const alive=()=>{const next=getContext();return current===sequence&&next.userId===context.userId&&next.epoch===context.epoch&&eligible(next);};
    const task=(async()=>{
      try{
        const{data,error}=await context.db.rpc('get_pending_member_count');
        if(!alive())return;
        const count=Number(data);
        if(error||data===null||!Number.isSafeInteger(count)||count<0){element.hidden=true;close();return;}
        for(const label of element.querySelectorAll('[data-pending-count]'))label.textContent=String(count);
        const message=element.querySelector('[data-pending-message]'),badge=element.querySelector('[data-pending-badge]');
        if(message)message.textContent=count?'가입 대기 중인 회원이 있습니다.':'가입 대기 중인 회원이 없습니다.';
        if(badge)badge.hidden=count===0;
        element.dataset.pending=String(count>0);
        button?.setAttribute('aria-label',`가입 대기 알림 ${count}명`);
        element.hidden=false;if(count===0)close();
      }catch{if(alive()){element.hidden=true;close();}}
    })();
    inFlight=task;
    try{await task;}finally{if(inFlight===task)inFlight=null;}
  }
  return {refresh,clear};
}
