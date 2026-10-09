const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function restrictionActive(member,now=Date.now()){
  if(!member)return false;
  if(member.status==='suspended'||member.is_restricted===true)return true;
  const start=Date.parse(member.restriction_start),end=Date.parse(member.restriction_end),current=now+(Number(member.server_clock_offset)||0);
  return Number.isFinite(start)&&Number.isFinite(end)&&current>=start&&current<end;
}
export const hasRestriction=member=>member?.status==='suspended'||Boolean(member?.restriction_start&&member?.restriction_end);
export const formatRestrictionDate=value=>value?new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',year:'numeric',month:'long',day:'numeric',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(value)):'';
export const toSeoulInput=value=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(value)).replace(' ','T');
export function seoulInputToIso(value){if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value))throw new Error('Invalid restriction dates');const date=new Date(`${value}:00+09:00`);if(!Number.isFinite(date.getTime()))throw new Error('Invalid restriction dates');return date.toISOString();}
export function restrictionLabel(member){if(restrictionActive(member))return '이용 제한';if(member?.restriction_start&&Date.parse(member.restriction_start)>Date.now())return '제한 예정';return null;}
export function restrictionView(member,{preview=false}={}){
  return `<section class="restriction-panel"><div class="access-icon" aria-hidden="true"><svg viewBox="0 0 24 24"><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/></svg></div><h1>${preview?'이용 제한 안내':'이용이 제한된 계정입니다'}</h1><p>${esc(member.nickname||'회원')}님은 제한 기간 동안 모든 게시판을 이용할 수 없습니다.</p><dl><div><dt>제한 시작</dt><dd>${esc(formatRestrictionDate(member.restriction_start)||'이용 제한 중')}</dd></div><div><dt>해제 예정일</dt><dd class="restriction-end">${esc(formatRestrictionDate(member.restriction_end)||'운영진 확인 후 해제')}</dd></div>${member.restriction_reason?`<div><dt>사유</dt><dd>${esc(member.restriction_reason)}</dd></div>`:''}</dl><p class="restriction-help">${member.restriction_end?'해제 일시부터 자동으로 이용할 수 있습니다.':'자세한 내용은 운영진에게 문의해 주세요.'}</p>${preview?'<a class="secondary" href="#/admin">회원관리로 돌아가기</a>':'<button class="secondary" type="button" id="restriction-check">제한 상태 다시 확인</button>'}</section>`;
}
