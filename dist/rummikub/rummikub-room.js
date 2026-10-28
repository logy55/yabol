import {betField,betBadge,betNotice} from './bets.js';
import {renderMonthlyRanking} from './leaderboard-view.js';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function friendly(error){const s=error?.message||'';if(/Approved|member_required/.test(s))return '로그인한 승인 회원만 참여할 수 있습니다.';if(/full/.test(s))return '방이 가득 찼습니다.';if(/Host/.test(s))return '방장만 변경할 수 있습니다.';if(/Not your turn|Turn changed/.test(s))return '차례가 바뀌었습니다. 현재 게임판을 다시 확인해 주세요.';if(/starting/.test(s))return '이미 시작한 경기입니다.';if(/membership|not found|closed/.test(s))return '방에서 나왔거나 방이 종료되었습니다.';if(/capacity/.test(s))return '참가 인원은 현재 인원 이상, 최대 4명이어야 합니다.';if(/rate|limit/.test(s))return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';return s&&!/fetch|network|invoke|unavailable/i.test(s)?s:'연결하지 못했습니다. 잠시 후 다시 시도해 주세요.';}
export async function renderRummikubRoom(main,{db,actor,onAuth=()=>{},signal,isCurrent=()=>true,request}={}){
 const approved=actor?.user_metadata?.status==='approved',key='yabol-rummi-room:'+actor?.id;
 const api=request||(async body=>{if(!db)throw Error('Service unavailable');let {data,error}=await db.functions.invoke('rummikub-room',{body});if(error?.context?.json){try{data=await error.context.json();}catch{}}if(error||data?.error){const e=Error(data?.error||error?.message||'Service unavailable');e.room=data?.room;throw e;}return data;});
 main.innerHTML='<section class="rummikub-room-page tool-page"><div class="board-heading"><div><p class="eyebrow">YABOL MINI GAME</p><h1>루미큐브</h1></div></div><p class="rummi-error" role="alert"></p><div class="rummi-lobby"></div><div class="rummi-current" hidden></div><section class="rummi-monthly rummi-card" aria-label="회원 전체 월간 랭킹"></section></section>';
 const root=main.querySelector('.rummikub-room-page'),$=s=>root.querySelector(s),alive=()=>!signal?.aborted&&isCurrent()&&main.contains(root);
 let room=null,queue=Promise.resolve(),pending=0,polling=false,generation=0,autoOpened='',offset=0,revision=-1,leaving=false;
 let ranking=null,rankBusy=false,rankFetchedAt=0,rankOffset=0,rankExpired=false,rankResultKey='';
 const popup=document.createElement('dialog');popup.className='rummi-online-modal';popup.setAttribute('aria-label','루미큐브 게임');
 const frame=document.createElement('iframe');frame.title='루미큐브 게임판';
 const previewMobile=new URLSearchParams(location.search).get('mobile')==='1';if(previewMobile)popup.dataset.mobilePreview='true';
 frame.src=new URL('./play.html?online=1'+(previewMobile?'&mobile=1':''),import.meta.url).href;popup.append(frame);document.body.append(popup);
 const store=id=>{try{if(id)localStorage.setItem(key,id);else localStorage.removeItem(key);}catch{}};
 const error=text=>{$('.rummi-error').textContent=text;};
 function sendView(force=false,message=''){if(room?.game)frame.contentWindow?.postMessage({type:'rummi-snapshot',room,force,error:message},location.origin);}
 function openGame(){if(!room?.game)return;if(!popup.open)popup.showModal();document.body.classList.add('rummi-room-open');sendView();}
 function closeGame(){if(popup.open)popup.close();document.body.classList.remove('rummi-room-open');}
 frame.onload=()=>sendView(true);
 popup.addEventListener('cancel',event=>{event.preventDefault();if(room?.phase==='finished')void mutate('leave');else closeGame();});
 function accept(next,force=false){
  if(!alive()||!next)return;if(room?.id===next.id&&next.revision<revision)return;
  const redraw=!room||room.id!==next.id||next.revision!==revision;
  if(room?.game&&!next.game)closeGame();room=next;revision=next.revision;offset=next.serverTime-Date.now();store(next.id);
  if(redraw)drawRoom();sendView(force);
  const playKey=room.id+':'+room.round+':'+(room.phase==='finished'?'result':'play');
  if(room.game&&autoOpened!==playKey){autoOpened=playKey;openGame();}
  if(room.phase==='finished'&&rankResultKey!==room.id+':'+room.round){rankResultKey=room.id+':'+room.round;void refreshRanking(true);}
 }
 function mutate(action,fields={}){
  if(action==='leave'&&leaving)return queue;if(action==='leave')leaving=true;
  pending++;queue=queue.catch(()=>{}).then(async()=>{
   if(!alive()){pending--;if(action==='leave')leaving=false;return;}error('');
   try{const result=await api({action,roomId:room?.id,...fields});if(!alive())return;if(result.left){await lobbyBack();return;}if(result.room)accept(result.room,['commit','draw'].includes(action));}
   catch(e){if(!alive())return;const text=friendly(e);error(text);if(e.room)accept(e.room,true);sendView(true,text);if(/membership|not found|closed/.test(e.message))await lobbyBack(text);}
   finally{pending--;if(action==='leave')leaving=false;}
  });return queue;
 }
 function lobby(){
  $('.rummi-current').hidden=true;$('.rummi-lobby').hidden=false;
  $('.rummi-lobby').innerHTML=approved?`<div class="room-lobby-grid"><div class="tool-card"><h2>대기방 만들기</h2><form id="rummi-create"><div class="tool-fields"><label>참여 인원<select name="capacity">${[2,3,4].map(n=>`<option value="${n}" ${n===4?'selected':''}>${n}명</option>`).join('')}</select></label>${betField()}</div><p class="form-note">방을 만든 회원이 방장입니다. 시작 전 방장이 인원과 내기를 설정합니다.</p><button class="primary" type="submit">방 만들기</button></form></div><div class="tool-card room-list-card"><h2>대기방 목록</h2><div class="rummi-list room-list" aria-live="polite"><div class="empty">대기방을 불러오는 중입니다.</div></div></div></div>`:'<div class="rummi-card"><p>승인된 회원이 로그인하면 참여할 수 있습니다.</p><button type="button" class="primary" id="rummi-login">로그인</button></div>';
  $('#rummi-login')?.addEventListener('click',onAuth);
  $('#rummi-create')?.addEventListener('submit',event=>{event.preventDefault();if(pending)return;void mutate('create',{capacity:Number(event.currentTarget.elements.capacity.value),bet:event.currentTarget.elements.bet.value});});
 }
 function drawList(rooms){
  const list=$('.rummi-list');if(!list||room)return;
  const html=rooms.length?rooms.map(r=>`<div class="rummi-list-row"><div><strong>${esc(r.host)}님의 방</strong><span>${r.count} / ${r.capacity}명</span>${betBadge(r.bet)}</div><button class="secondary" type="button" data-join="${esc(r.code)}" ${r.count>=r.capacity?'disabled':''}>입장</button></div>`).join(''):'<p class="rummi-empty">열려 있는 대기방이 없습니다.</p>';
  if(list.innerHTML!==html){list.innerHTML=html;for(const button of list.querySelectorAll('[data-join]'))button.onclick=()=>void mutate('join',{code:button.dataset.join});}
 }
 function drawRoom(){
  const me=room.members.find(m=>m.id===actor.id),host=room.hostId===actor.id,waiting=['waiting','countdown'].includes(room.phase),finished=room.phase==='finished';
  $('.rummi-lobby').hidden=true;$('.rummi-current').hidden=false;
  $('.rummi-current').innerHTML=`<div class="rummi-card"><div class="rummi-room-title"><h2>${esc(room.members.find(m=>m.id===room.hostId)?.name||'방장')}님의 방</h2><span>${room.members.length}/${room.capacity}명</span></div>${host&&room.phase==='waiting'?`<form id="rummi-settings"><label>참가 인원<select name="capacity">${[2,3,4].map(n=>`<option value="${n}" ${n===room.capacity?'selected':''} ${n<room.members.length?'disabled':''}>${n}명</option>`).join('')}</select></label>${betField(room.bet)}<button class="secondary" type="submit">설정 변경</button></form>`:''}${betNotice(room.bet)}<details class="rummi-scoring"><summary>점수 · 동점 처리 기준</summary><p>공식 Classic 점수: 승자는 다른 회원의 벌점 합, 나머지는 남은 타일 숫자 합의 음수입니다. 조커는 30점이며 미등록 추가 벌점은 없습니다.</p><p>공식 점수가 같으면 공동 순위입니다. 내기 꼴찌는 남은 타일 수 → 큰 타일부터 비교 → 완전 동점자 숫자 추첨으로 정합니다.</p></details><div class="rummi-seats">${Array.from({length:room.capacity},(_,i)=>{const m=room.members[i];return m?`<div class="rummi-seat" data-ready="${m.ready}"><span class="rummi-avatar">${esc(m.name[0])}</span><strong>${esc(m.name)}</strong><small>${m.id===room.hostId?'방장 · ':''}${waiting?(m.ready?'준비 완료':'준비 중'):'참가 중'}</small>${host&&m.id!==actor.id&&waiting?`<button type="button" class="rummi-kick" data-kick="${esc(m.id)}">추방</button>`:''}</div>`:'<div class="rummi-seat empty"><span>＋</span><small>입장 대기</small></div>';}).join('')}</div><div class="rummi-room-controls">${waiting?`<button type="button" class="primary" id="rummi-ready">${me?.ready?'준비 취소':'준비'}</button>`:room.game?`<button type="button" class="primary" id="rummi-open">${finished?'결과 보기':'경기 화면 열기'}</button>`:''}${!finished?'<button type="button" class="secondary" id="rummi-leave">나가기</button>':''}</div><p class="rummi-leave-note" hidden></p><p class="rummi-stage" role="status"></p>${room.message?`<p class="rummi-message">${esc(room.message)}</p>`:''}</div>`;
  $('#rummi-ready')?.addEventListener('click',()=>void mutate('ready',{ready:!me.ready}));$('#rummi-open')?.addEventListener('click',openGame);
  $('#rummi-settings')?.addEventListener('submit',event=>{event.preventDefault();void mutate('settings',{capacity:Number(event.currentTarget.elements.capacity.value),bet:event.currentTarget.elements.bet.value});});
  for(const b of root.querySelectorAll('[data-kick]'))b.onclick=()=>void mutate('kick',{userId:b.dataset.kick});
  $('#rummi-leave')?.addEventListener('click',()=>{
   const note=$('.rummi-leave-note');
   if(waiting&&me?.ready){note.hidden=false;note.innerHTML="준비를 해제한 뒤 나갈 수 있습니다.<br>'준비 취소'를 먼저 눌러주세요.";return;}
   if(room.phase==='running'){note.hidden=false;note.textContent='경기 진행 중에는 나갈 수 없습니다. 경기 화면을 닫아도 턴 시간은 계속 흐릅니다.';return;}
   void mutate('leave');
  });tick();
 }
 async function refreshRanking(force=false){
  if(!alive()||!approved||rankBusy||(!force&&Date.now()-rankFetchedAt<15000))return;
  rankBusy=true;rankFetchedAt=Date.now();
  try{const result=await api({action:'leaderboard'});if(!alive())return;ranking=result.leaderboard;rankOffset=ranking.serverNow-Date.now();rankExpired=false;renderMonthlyRanking($('.rummi-monthly'),ranking,{viewerId:actor.id});}
  catch(e){if(alive())renderMonthlyRanking($('.rummi-monthly'),ranking,{viewerId:actor.id,error:friendly(e)});}
  finally{rankBusy=false;}
 }
 function tick(){
  if(!alive())return;
  if(ranking&&!rankExpired&&Date.now()+rankOffset>=ranking.resetsAt){rankExpired=true;renderMonthlyRanking($('.rummi-monthly'),null,{loading:true,viewerId:actor.id});void refreshRanking(true);}
  if(!room)return;const e=$('.rummi-stage');if(!e)return;const now=Date.now()+offset;
  e.textContent=room.phase==='countdown'?Math.max(0,Math.ceil((room.startAt-now)/1000))+'초 후 시작합니다.':room.phase==='waiting'?'모두 준비되면 5초 후 시작합니다.':room.phase==='running'?(room.game.players.find(p=>p.id===room.game.currentId)?.name||'회원')+' 님 차례입니다.':room.phase==='finished'?'경기가 종료되었습니다.':'대기방이 종료되었습니다.';
 }
 async function lobbyBack(message=''){generation++;room=null;revision=-1;autoOpened='';store(null);closeGame();lobby();error(message);void refreshRanking(true);await poll();}
 async function poll(){
  if(!alive()||pending||polling||!approved)return;polling=true;const ticket=++generation;
  try{const result=await api(room?{action:'get',roomId:room.id}:{action:'list'});if(!alive()||ticket!==generation)return;if(result.room)accept(result.room);else drawList(result.rooms||[]);}
  catch(e){if(!alive())return;error(friendly(e));if(/membership|not found|closed/.test(e.message)){room=null;store(null);closeGame();lobby();}}
  finally{polling=false;}
 }
 const onMessage=event=>{
  if(event.origin!==location.origin||event.source!==frame.contentWindow||!alive())return;const data=event.data;
  if(data?.type==='rummi-ready'){sendView(true);return;}if(data?.type!=='rummi-action')return;
  if(data.action==='close'){if(room?.phase==='finished')void mutate('leave');else closeGame();return;}
  if(data.action==='leave'){if(room?.phase==='finished')void mutate('leave');return;}
  if(['draft','commit','draw'].includes(data.action))void mutate(data.action,{turn:data.turn,draft:data.draft});
 };
 window.addEventListener('message',onMessage);
 const onVisible=()=>{if(!document.hidden){tick();void poll();void refreshRanking();}};
 document.addEventListener('visibilitychange',onVisible);window.addEventListener('online',onVisible);
 const clock=setInterval(tick,200),poller=setInterval(()=>void poll(),1000),rankPoller=setInterval(()=>{if(!document.hidden&&!popup.open)void refreshRanking();},15000);
 signal?.addEventListener('abort',()=>{generation++;clearInterval(clock);clearInterval(poller);clearInterval(rankPoller);window.removeEventListener('message',onMessage);document.removeEventListener('visibilitychange',onVisible);window.removeEventListener('online',onVisible);closeGame();popup.remove();},{once:true});
 lobby();renderMonthlyRanking($('.rummi-monthly'),null,{loading:approved,viewerId:actor?.id});$('.rummi-monthly').hidden=!approved;
 let saved;try{saved=localStorage.getItem(key);}catch{}if(saved&&approved){try{const result=await api({action:'get',roomId:saved});accept(result.room);}catch{store(null);}}
 await Promise.all([poll(),refreshRanking(true)]);
}
