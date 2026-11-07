import {gameRecordSections,validateGameRecords,activitySections} from './account.js?v=20261107-rummikub-bets';
import{memberName}from'./teams.js?v=20261024-member-records';
import {restrictionActive} from './restrictions.js?v=20261010-member-fixes';
const approved=actor=>actor?.user_metadata?.status==='approved'&&!restrictionActive(actor.user_metadata);
export function createMemberGameRecords({context,onAuth=()=>{}}){
  const menu=document.createElement('div');menu.className='member-game-menu';menu.hidden=true;menu.setAttribute('role','menu');menu.setAttribute('aria-label','회원 메뉴');
  menu.innerHTML='<button type="button" role="menuitem">정보 보기</button>';
  const dialog=document.createElement('dialog');dialog.className='dialog member-game-dialog';dialog.setAttribute('aria-labelledby','member-game-title');
  dialog.innerHTML='<div class="dialog-top"><h2 id="member-game-title">회원 정보</h2><button type="button" class="icon-button" aria-label="정보 닫기">×</button></div><div class="member-game-body"></div>';
  document.body.append(menu,dialog);
  let trigger=null,selected=null,request=0,viewer=null;
  const body=dialog.querySelector('.member-game-body'),item=menu.querySelector('button');
  function closeMenu(focus=false){menu.hidden=true;trigger?.setAttribute('aria-expanded','false');if(focus&&trigger?.isConnected)trigger.focus();}
  function close(){closeMenu();request++;if(dialog.open)dialog.close();}
  function sync(){const next=context();if(!approved(next.actor)||viewer&&(viewer.id!==next.actor?.id||viewer.epoch!==next.epoch))close();}
  async function show(target){
    const current=context();closeMenu();
    if(!current.db||!approved(current.actor)){close();onAuth();return;}
    selected=target;viewer={id:current.actor.id,epoch:current.epoch};const id=++request;
    dialog.querySelector('h2').textContent=target.name+'님의 정보';
    body.innerHTML=gameRecordSections(null,{prefix:'member'});if(!dialog.open)dialog.showModal();
    try{
      const{data,error}=await current.db.rpc('get_member_info',{p_user:target.id});if(error)throw error;
      const next=context();if(id!==request||!dialog.open||!approved(next.actor)||next.actor.id!==viewer.id||next.epoch!==viewer.epoch)return;
      validateGameRecords(data);body.innerHTML=memberInfoMarkup(data);
    }catch(error){
      if(id!==request||!dialog.open)return;
      body.innerHTML=error?.message?.includes('Member not found')?'<p class="form-error" role="alert">이 회원의 정보를 확인할 수 없습니다.</p>':'<p class="form-error" role="alert">정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.</p>';
    }
  }
  function openMenu(button){
    const current=context();if(!current.db||!approved(current.actor)){onAuth();return;}
    if(trigger===button&&!menu.hidden){closeMenu();return;}
    closeMenu();trigger=button;selected={id:button.dataset.gameMemberId,name:button.dataset.memberName||'회원'};viewer={id:current.actor.id,epoch:current.epoch};
    trigger.setAttribute('aria-expanded','true');menu.hidden=false;
    const rect=button.getBoundingClientRect();menu.style.left=Math.max(12,Math.min(rect.left,innerWidth-menu.offsetWidth-12))+'px';menu.style.top=Math.max(12,Math.min(rect.bottom+6,innerHeight-menu.offsetHeight-12))+'px';item.focus();
  }
  document.addEventListener('click',event=>{
    const button=event.target.closest('.member-record-trigger');
    if(button){event.preventDefault();openMenu(button);return;}
    if(!menu.contains(event.target))closeMenu();
  });
  item.onclick=()=>{if(selected)void show({...selected});};
  dialog.querySelector('.icon-button').onclick=()=>dialog.close();
  dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
  dialog.addEventListener('close',()=>{request++;body.innerHTML='';if(trigger?.isConnected)trigger.focus();});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!menu.hidden){event.preventDefault();closeMenu(true);}});
  document.addEventListener('scroll',()=>closeMenu(),true);window.addEventListener('resize',()=>closeMenu());window.addEventListener('hashchange',close);
  return {sync,close};
}

const memberInfoEscape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function memberInfoMarkup(data){const p=data.profile;if(!p||typeof p.nickname!=='string'||!Number.isFinite(Date.parse(p.created_at)))throw Error('Invalid member profile');const joined=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',year:'numeric',month:'long',day:'numeric'}).format(new Date(p.created_at));return `<div class="member-info-profile"><strong class="member-identity">${memberName(p.nickname,p.team,p.region,p.staff_role,p.is_yb_member)}</strong><dl><div><dt>가입일</dt><dd>${memberInfoEscape(joined)}</dd></div></dl></div>${activitySections(data.activity,{prefix:'member'})}${gameRecordSections(data,{prefix:'member'})}`;}
