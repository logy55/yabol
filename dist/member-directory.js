import{memberName,getTeam}from'./teams.js?v=20261024-member-records';
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}),collator=new Intl.Collator('ko-KR',{sensitivity:'base',numeric:true});
export function normalizeDirectory(data){
 if(!data||!Number.isSafeInteger(data.total)||data.total<0||!Array.isArray(data.members)||data.total!==data.members.length)throw Error('Invalid directory');
 const members=data.members.map(m=>{
  if(!m||typeof m.id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(m.id)||typeof m.nickname!=='string'||!m.nickname.trim()||!Number.isFinite(Date.parse(m.created_at)))throw Error('Invalid member');
  return{id:m.id,nickname:m.nickname,region:typeof m.region==='string'?m.region:'',team:typeof m.team==='string'?m.team:null,staff_role:['staff','vice_staff'].includes(m.staff_role)?m.staff_role:'member',is_yb_member:m.is_yb_member===true,created_at:m.created_at};
 });return{total:data.total,members};
}
export function groupDirectory(members,query=''){
 const groups=new Map(),q=query.trim().toLocaleLowerCase('ko-KR');
 for(const m of members){if(q&&!(m.nickname+' '+m.region).toLocaleLowerCase('ko-KR').includes(q))continue;const team=getTeam(m.team),key=team?.id||'none';if(!groups.has(key))groups.set(key,{team:key,name:team?.name||'응원 구단 미선택',members:[]});groups.get(key).members.push(m);}
 const bucket=g=>g.team==='none'?2:/^[가-힣ㄱ-ㅎ]/.test(g.name)?0:1;
 return[...groups.values()].sort((a,b)=>bucket(a)-bucket(b)||collator.compare(a.name,b.name)).map(g=>({...g,members:g.members.sort((a,b)=>collator.compare(a.nickname,b.nickname)||a.id.localeCompare(b.id))}));
}
export function memberCards(members){return members.map(m=>`<li class="member-directory-card"><div class="member-directory-identity">${memberName(m.nickname,m.team,'',m.staff_role,m.is_yb_member,m.id)}</div><p class="member-directory-region">${esc(m.region||'지역 미등록')}</p><time datetime="${esc(m.created_at)}">가입 ${date.format(new Date(m.created_at))}</time></li>`).join('');}
export async function renderMemberDirectory(main,{db,signal,isCurrent=()=>true}={}){
 const alive=()=>!signal?.aborted&&isCurrent();if(!alive())return;
 main.innerHTML=`<section class="member-directory"><div class="board-heading"><div><h1>회원목록</h1><p>전체 회원 <strong id="directory-total">—</strong>명</p></div></div><form class="member-directory-search" role="search"><label class="sr-only" for="directory-query">회원 이름·지역 검색</label><input id="directory-query" name="query" type="search" maxlength="80" placeholder="이름·지역 검색" autocomplete="off"><button type="submit" class="primary">검색</button></form><p class="member-directory-status" role="status" aria-live="polite"></p><div class="member-directory-groups"></div></section>`;
 const root=main.querySelector('.member-directory'),container=root.querySelector('.member-directory-groups'),status=root.querySelector('[role=status]'),form=root.querySelector('form');let members=[],query='',sequence=0;
 function draw(){const groups=groupDirectory(members,query);container.innerHTML=groups.map(g=>`<section class="member-directory-team" aria-labelledby="directory-team-${g.team}"><h2 id="directory-team-${g.team}">${esc(g.name)} <span>(${g.members.length}명)</span></h2><ul class="member-directory-grid" aria-label="${esc(g.name)} 회원">${memberCards(g.members)}</ul></section>`).join('');status.textContent=groups.length?'':query?'검색 결과가 없습니다.':'아직 등록된 회원이 없습니다.';}
 async function load(){const request=++sequence;container.replaceChildren();container.setAttribute('aria-busy','true');status.textContent='회원목록을 불러오는 중입니다.';
  try{if(!db)throw Error('Unavailable');const{data,error}=await db.rpc('get_member_directory');if(error)throw error;if(!alive()||request!==sequence)return;const result=normalizeDirectory(data);members=result.members;root.querySelector('#directory-total').textContent=result.total.toLocaleString('ko-KR');draw();
  }catch{if(!alive()||request!==sequence)return;status.innerHTML='회원목록을 불러오지 못했습니다. <button type="button" class="text-button">다시 시도</button>';status.querySelector('button').onclick=()=>void load();
  }finally{if(alive()&&request===sequence)container.removeAttribute('aria-busy');}
 }
 form.onsubmit=event=>{event.preventDefault();query=form.elements.query.value;draw();};form.elements.query.addEventListener('search',()=>{query=form.elements.query.value;draw();});await load();
}
