// dist/core.js
const COLOURS=['black','blue','red','gold'];
const COLOUR_NAMES=['검정','파랑','빨강','주황'];
function tile(id){if(!Number.isInteger(id)||id<0||id>105)throw Error('잘못된 타일입니다.');return id>=104?{id,joker:true,value:0,colour:null}:{id,joker:false,value:id%13+1,colour:Math.floor(id/26)};}
function tileId(colour,value,copy=0){return colour*26+copy*13+value-1;}
const tileValue=id=>id>=104?30:tile(id).value;
function setInfo(ids){
 if(ids.length<3)return{valid:false,message:'3장 이상 필요해요.'};if(ids.length>13||new Set(ids).size!==ids.length)return{valid:false,message:'중복 타일을 확인해 주세요.'};
 const tiles=ids.map(tile),normal=tiles.filter(t=>!t.joker),options=[];
 if(ids.length<=4&&normal.length&&normal.every(t=>t.value===normal[0].value)&&new Set(normal.map(t=>t.colour)).size===normal.length)options.push({valid:true,kind:'group',label:'그룹',score:normal[0].value*ids.length});
 const first=tiles.findIndex(t=>!t.joker);if(first>=0){const start=tiles[first].value-first,colour=tiles[first].colour;if(start>=1&&start+ids.length-1<=13&&tiles.every((t,i)=>t.joker||t.colour===colour&&t.value===start+i))options.push({valid:true,kind:'run',label:'런',score:ids.length*(start*2+ids.length-1)/2});}
 return options.sort((a,b)=>b.score-a.score)[0]||{valid:false,message:'같은 숫자·다른 색, 또는 같은 색·연속 숫자로 놓아 주세요.'};
}
const clone=state=>structuredClone(state),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b),sorted=ids=>[...ids].sort((a,b)=>a-b);
class TileGame{
 constructor({players=4,names=[],seed=Date.now(),practice=true,random=null}={}){
  if(random)Object.defineProperty(this,'randomOverride',{value:random});
  if(!Number.isInteger(players)||players<2||players>4)throw Error('2~4명이 플레이할 수 있어요.');this.seed=seed>>>0;this.players=Array.from({length:players},(_,i)=>({name:String(names[i]||'플레이어 '+(i+1)).trim().slice(0,14)||'플레이어 '+(i+1),rack:[],opened:false}));this.table=[];this.pool=Array.from({length:106},(_,i)=>i);this.current=0;this.turn=1;this.nextGroup=1;this.history=[];this.over=false;this.result=null;this.dryPasses=0;
  if(practice){const take=ids=>{for(const id of ids){const at=this.pool.indexOf(id);if(at<0)throw Error('중복 타일');this.pool.splice(at,1);}return ids;};this.table=[take([tileId(2,3),tileId(2,4),tileId(2,5)]),take([tileId(0,7),tileId(1,7),tileId(3,7)]),take([tileId(0,10),tileId(0,11),tileId(0,12),104]),take([tileId(1,3),tileId(1,4),tileId(1,5),tileId(1,6)]),take([tileId(2,11),tileId(1,11,1),tileId(3,11,1)]),take([tileId(3,3,1),tileId(3,4,1),tileId(3,5,1),tileId(3,6,1)]),take([tileId(0,2),tileId(1,2),tileId(2,2,1)]),take([tileId(2,9,1),tileId(2,10,1),tileId(2,11,1),tileId(2,12,1)])].map(tiles=>({id:this.nextGroup++,tiles}));this.players[0].rack=take([tileId(1,10),tileId(1,11),tileId(1,12),105,tileId(2,8),tileId(3,8),tileId(0,8),tileId(1,9),tileId(2,2),tileId(2,6),tileId(3,11),tileId(0,3),tileId(3,4),tileId(0,13)]);this.players.slice(1).forEach(p=>p.opened=true);}
  this.shuffle();if(!practice){let tied=this.players.map((_,i)=>i);this.starterDraw=[];while(tied.length>1){const bag=[...this.pool],draws=tied.map(player=>{const at=Math.floor(this.random()*bag.length),id=bag.splice(at,1)[0];return{player,tile:id,value:tile(id).value};}),highest=Math.max(...draws.map(d=>d.value));this.starterDraw.push(draws);tied=draws.filter(d=>d.value===highest).map(d=>d.player);}this.current=tied[0];this.shuffle();}for(const p of this.players)while(p.rack.length<14)p.rack.push(this.pool.pop());this.beginTurn();
 }
 random(){if(this.randomOverride)return this.randomOverride();this.seed=(Math.imul(this.seed,1664525)+1013904223)>>>0;return this.seed/4294967296;}
 shuffle(){for(let i=this.pool.length-1;i>0;i--){const j=Math.floor(this.random()*(i+1));[this.pool[i],this.pool[j]]=[this.pool[j],this.pool[i]];}}
 beginTurn(){this.original={table:clone(this.table),rack:[...this.players[this.current].rack]};this.draft={table:clone(this.table),rack:[...this.players[this.current].rack]};this.history=[];}
 get player(){return this.players[this.current];}
 get added(){return this.original.rack.filter(id=>!this.draft.rack.includes(id));}
 get changed(){return !same(this.draft.table,this.original.table)||!same(sorted(this.draft.rack),sorted(this.original.rack));}
 get initialPoints(){return this.draft.table.filter(g=>!this.original.table.some(o=>o.id===g.id)).reduce((s,g)=>s+(setInfo(g.tiles).valid?setInfo(g.tiles).score:0),0);}
 checkpoint(){this.history.push(clone(this.draft));if(this.history.length>80)this.history.shift();}
 move(ids,target={kind:'new'}){
  if(this.over)throw Error('종료된 경기입니다.');if(!Array.isArray(ids)||!ids.length||new Set(ids).size!==ids.length)throw Error('옮길 타일을 선택해 주세요.');
  const available=[...this.draft.rack,...this.draft.table.flatMap(g=>g.tiles)];if(ids.some(id=>!available.includes(id)))throw Error('해당 타일을 찾을 수 없어요.');
  if(!this.player.opened&&ids.some(id=>!this.original.rack.includes(id)))throw Error('최초 등록 전에는 내 타일로만 새 조합을 만들어 주세요.');
  if(target.kind==='rack'&&ids.some(id=>!this.original.rack.includes(id)))throw Error('공용판 타일은 내 받침대로 가져올 수 없어요.');
  const destination=this.draft.table.find(g=>g.id===target.group);
  if(target.kind==='group'&&!destination)throw Error('조합을 찾을 수 없어요.');
  if(target.kind==='group'&&!this.player.opened&&this.original.table.some(g=>g.id===target.group))throw Error('먼저 내 타일만으로 30점 이상 등록해 주세요.');
  if(!['rack','group','new'].includes(target.kind))throw Error('놓을 곳을 선택해 주세요.');
  const next=clone(this.draft);next.rack=next.rack.filter(id=>!ids.includes(id));let insertion=target.index??destination?.tiles.length??0;if(destination)insertion-=destination.tiles.slice(0,insertion).filter(id=>ids.includes(id)).length;
  for(const group of next.table)group.tiles=group.tiles.filter(id=>!ids.includes(id));
  if(target.kind==='rack'){const index=Math.max(0,Math.min(next.rack.length,target.index??next.rack.length));next.rack.splice(index,0,...ids);}else if(target.kind==='new')next.table.push({id:this.nextGroup++,tiles:[...ids]});else{const group=next.table.find(g=>g.id===target.group);group.tiles.splice(Math.max(0,Math.min(group.tiles.length,insertion)),0,...ids);}
  next.table=next.table.filter(g=>g.tiles.length);if(same(this.draft,next))return false;this.checkpoint();this.draft=next;return true;
 }
 undo(){if(!this.history.length)return false;this.draft=this.history.pop();return true;}
 reset(){if(!this.changed)return false;this.checkpoint();this.draft={table:clone(this.original.table),rack:[...this.original.rack]};return true;}
 sort(mode='colour'){const key=id=>{const t=tile(id);return t.joker?999:mode==='number'?t.value*10+t.colour:t.colour*20+t.value;};this.draft.rack.sort((a,b)=>key(a)-key(b)||a-b);}
 validate(){
  const before=[...this.original.rack,...this.original.table.flatMap(g=>g.tiles)],after=[...this.draft.rack,...this.draft.table.flatMap(g=>g.tiles)];if(!same(sorted(before),sorted(after))||new Set(after).size!==after.length)throw Error('타일이 빠지거나 중복됐어요. 되돌리기를 눌러 주세요.');
  const invalid=this.draft.table.find(g=>!setInfo(g.tiles).valid);if(invalid)throw Error('아직 완성되지 않은 조합이 있어요. '+setInfo(invalid.tiles).message);
  if(!this.added.length)throw Error('내 타일을 1장 이상 놓거나, 먹고 넘기기를 눌러 주세요.');
  if(!this.player.opened){for(const original of this.original.table){const now=this.draft.table.find(g=>g.id===original.id);if(!now||!same(now.tiles,original.tiles))throw Error('최초 등록 전에는 공용판을 바꿀 수 없어요.');}if(this.initialPoints<30)throw Error('첫 등록은 내 타일로 합계 30점 이상이어야 해요. 현재 '+this.initialPoints+'점입니다.');}
  return{played:this.added.length,points:this.initialPoints};
 }
 commit(){const info=this.validate(),who=this.current;this.table=clone(this.draft.table);this.player.rack=[...this.draft.rack];this.player.opened=true;this.dryPasses=0;if(!this.player.rack.length){this.finish([who],'empty');return{...info,over:true,who};}this.advance();return{...info,over:false,who};}
 draw(count=1){if(this.over)return;const who=this.current;this.draft={table:clone(this.original.table),rack:[...this.original.rack]};let drawn=0;while(drawn<count&&this.pool.length){this.player.rack.push(this.pool.pop());drawn++;}if(!drawn)this.dryPasses++;else this.dryPasses=0;if(this.dryPasses>=this.players.length){const totals=this.players.map(p=>p.rack.reduce((s,id)=>s+tileValue(id),0)),least=Math.min(...totals);this.finish(totals.flatMap((n,i)=>n===least?[i]:[]),'blocked');return{who,drawn,over:true};}this.advance();return{who,drawn,over:false};}
 timeout(){if(this.changed){try{return{...this.commit(),automatic:true};}catch{return{...this.draw(3),penalty:true};}}return this.draw(1);}
 advance(){do{this.current=(this.current+1)%this.players.length;}while(this.players[this.current].forfeited);this.turn++;this.beginTurn();}
 finish(winners,reason){const values=this.players.map(p=>p.rack.reduce((s,id)=>s+tileValue(id),0)),base=['empty','forfeit'].includes(reason)?0:Math.min(...values),scores=values.map((v,i)=>winners.includes(i)?0:base-v),pot=-scores.reduce((s,n)=>s+n,0);for(let i=0;i<winners.length;i++)scores[winners[i]]=Math.floor(pot/winners.length)+(i<pot%winners.length?1:0);this.over=true;this.result={winners,reason,values,scores};}
}
function restoreGame(state){return Object.assign(Object.create(TileGame.prototype),structuredClone(state));}


// dist/bets.js
const roomBets=Object.freeze({none:{name:'내기 없음'},starbucks:{name:'스타벅스 아이스 아메리카노',image:'gift-starbucks.png',url:'https://gift.kakao.com/product/11062288'},mgc:{name:'메가커피 아이스 아메리카노',image:'gift-mgc.png',url:'https://gift.kakao.com/product/11561213'},compose:{name:'컴포즈커피 아이스 아메리카노',image:'gift-compose.png',url:'https://gift.kakao.com/product/11983723'}});
const betKeys=Object.keys(roomBets);
function betField(key='none'){return `<label class="rummi-bet-select"><span>내기 선택</span><select name="bet" aria-label="내기 선택">${Object.entries(roomBets).map(([value,bet])=>`<option value="${value}" ${value===key?'selected':''}>${bet.name}</option>`).join('')}</select></label>`;}
function betBadge(key){const bet=roomBets[key]||roomBets.none;return `<span class="rummi-bet-badge">${bet.image?`<img src="${new URL('./assets/'+bet.image,import.meta.url).href}" width="28" height="28" alt="">`:''}<span>${bet.name}</span></span>`;}
function betNotice(key){const bet=roomBets[key]||roomBets.none;return `<p class="rummi-bet-notice">${bet.image?`이번 경기에는 <img src="${new URL('./assets/'+bet.image,import.meta.url).href}" width="36" height="36" alt=""><strong>${bet.name}</strong> 내기가 걸려 있습니다.`:'이번 경기는 내기 없이 진행합니다.'}</p>`;}


// dist/room-core.js
const copy=value=>value===undefined?null:JSON.parse(JSON.stringify(value));
const fail=message=>{throw Error(message);};
const integer=(n,min,max)=>Number.isInteger(n)&&n>=min&&n<=max;
const active=room=>room.members.filter(m=>!m.left);
const member=(room,id)=>room.members.find(m=>m.id===id&&!m.left);
const gameState=g=>copy(g);
const secureRandom=()=>crypto.getRandomValues(new Uint32Array(1))[0]/4294967296;
function createRoom(actor,{capacity=4,bet='none'}={},now=Date.now()){
 if(!actor?.id||!actor.approved)fail('Approved member required');
 if(!integer(capacity,2,4))fail('Invalid capacity');if(!betKeys.includes(bet))fail('Invalid bet');
 return {id:crypto.randomUUID(),code:crypto.randomUUID().slice(0,6).toUpperCase(),hostId:actor.id,capacity,bet,phase:'waiting',revision:1,createdAt:now,updatedAt:now,startAt:null,deadline:null,finishedAt:null,round:1,game:null,outcome:null,message:'',members:[{id:actor.id,name:actor.name||'회원',ready:false,seen:now,left:false}]};
}
function touch(room,now){room.revision++;room.updatedAt=now;}
function finishOrAdvance(room,g,now){room.game=gameState(g);if(g.over){room.phase='finished';room.deadline=null;room.finishedAt=now;room.outcome=betOutcome(g);}else room.deadline=now+60000;}
function betOutcome(g,random=secureRandom){
 const lowest=Math.min(...g.result.scores);let candidates=g.players.flatMap((p,i)=>g.result.scores[i]===lowest?[i]:[]),reason='score',draws=[];
 if(candidates.length>1){const max=Math.max(...candidates.map(i=>g.players[i].rack.length));candidates=candidates.filter(i=>g.players[i].rack.length===max);reason='tile-count';}
 if(candidates.length>1){const values=i=>g.players[i].rack.map(tileValue).sort((a,b)=>b-a),compare=(a,b)=>{const x=values(a),y=values(b);for(let i=0;i<x.length;i++)if(x[i]!==y[i])return x[i]-y[i];return 0;};const highest=candidates.reduce((a,b)=>compare(a,b)>=0?a:b);candidates=candidates.filter(i=>compare(i,highest)===0);reason='tile-values';}
 if(candidates.length>1){const bag=Array.from({length:13},(_,i)=>i+1);draws=candidates.map(index=>({index,value:bag.splice(Math.floor(random()*bag.length),1)[0]}));candidates=[draws.reduce((a,b)=>a.value>b.value?a:b).index];reason='draw';}
 return {loserIndex:candidates[0],decidedBy:reason,draws,counts:g.players.map(p=>p.rack.length)};
}
function settleRoom(room,now=Date.now(),random=secureRandom){
 let changed=false;
 if(room.phase==='closed')return changed;
 if(now-Math.max(...active(room).map(m=>m.seen),room.createdAt)>20*60000){room.phase='closed';room.message='오랫동안 접속한 인원이 없어 방이 종료되었습니다.';touch(room,now);return true;}
 if(room.phase==='countdown'&&room.startAt<=now){
  const members=active(room),g=new TileGame({players:members.length,names:members.map(m=>m.name),practice:false,random});
  g.players.forEach((p,i)=>p.id=members[i].id);room.phase='running';room.game=gameState(g);room.deadline=room.startAt+60000;room.message='숫자 추첨으로 첫 번째 플레이어를 정했습니다.';changed=true;
 }
 let guard=0;
 while(room.phase==='running'&&room.deadline<=now&&guard++<100){
  const g=restoreGame(room.game),who=g.player.name,at=room.deadline,result=g.timeout();
  room.message=result?.penalty?who+' 님의 미완성 배치를 취소하고 3장을 먹었습니다.':result?.automatic?who+' 님의 완성된 배치를 자동 확정했습니다.':who+' 님이 시간 초과로 1장을 먹었습니다.';
  finishOrAdvance(room,g,at);changed=true;
 }
 if(changed)touch(room,now);return changed;
}
function applyDraft(g,draft){
 if(!draft||!Array.isArray(draft.rack)||!Array.isArray(draft.table)||draft.rack.length>106||draft.table.length>106)fail('Invalid draft');
 const groups=draft.table.map(s=>{if(!integer(s?.id,1,1000000)||!Array.isArray(s.tiles)||s.tiles.length<1||s.tiles.length>106)fail('Invalid draft');return{id:s.id,tiles:[...s.tiles]};});
 const expected=[...g.original.rack,...g.original.table.flatMap(s=>s.tiles)].sort((a,b)=>a-b),actual=[...draft.rack,...groups.flatMap(s=>s.tiles)].sort((a,b)=>a-b);
 if(actual.some(id=>!integer(id,0,105))||new Set(actual).size!==actual.length||JSON.stringify(actual)!==JSON.stringify(expected)||new Set(groups.map(s=>s.id)).size!==groups.length)fail('Tile ownership mismatch');
 if(g.original.table.some(s=>s.tiles.some(id=>draft.rack.includes(id))))fail('Table tile cannot enter rack');
 if(!g.player.opened&&g.original.table.some(s=>JSON.stringify(groups.find(t=>t.id===s.id)?.tiles)!==JSON.stringify(s.tiles)))fail('Initial meld cannot change table');
 g.draft={rack:[...draft.rack],table:groups};g.nextGroup=Math.max(g.nextGroup,...groups.map(s=>s.id+1));g.history=[];
}
function actRoom(room,actor,action,input={},now=Date.now(),random=secureRandom){
 if(!actor?.approved)fail('Approved member required');
 const me=member(room,actor.id);if(action!=='join'&&!me)fail('Room membership required');
 settleRoom(room,now,random);if(room.phase==='closed')fail('Room closed');
 if(action==='get'){if(now-me.seen>=10000){me.seen=now;touch(room,now);}return;}
 if(action==='join'){
  if(me){me.seen=now;touch(room,now);return;}
  if(room.phase!=='waiting')fail('Game already starting');if(active(room).length>=room.capacity)fail('Room full');
  room.members=room.members.filter(m=>m.id!==actor.id);room.members.push({id:actor.id,name:actor.name||'회원',ready:false,seen:now,left:false});
 }else if(action==='settings'){
  if(room.hostId!==actor.id)fail('Host required');if(room.phase!=='waiting')fail('Game already starting');
  if(!integer(input.capacity,2,4)||input.capacity<active(room).length)fail('Invalid capacity');if(!betKeys.includes(input.bet))fail('Invalid bet');room.capacity=input.capacity;room.bet=input.bet;active(room).forEach(m=>m.ready=false);
 }else if(action==='ready'){
  if(!['waiting','countdown'].includes(room.phase))fail('Game already starting');if(typeof input.ready!=='boolean')fail('Invalid readiness');me.ready=input.ready;
  if(active(room).length===room.capacity&&active(room).every(m=>m.ready)){if(room.phase!=='countdown'){room.phase='countdown';room.startAt=now+5000;}}
  else{room.phase='waiting';room.startAt=null;}
 }else if(action==='kick'||action==='leave'){
  const target=action==='kick'?input.userId:actor.id,victim=member(room,target);if(!victim)fail('Player not found');
  if(action==='kick'&&(room.hostId!==actor.id||target===actor.id))fail('Host required');
  if(['waiting','countdown'].includes(room.phase)){
   if(action==='leave'&&me.ready)fail('Cancel readiness before leaving');room.members=room.members.filter(m=>m.id!==target);active(room).forEach(m=>m.ready=false);room.phase='waiting';room.startAt=null;
  }else if(action==='kick')fail('Game already starting');
  else{if(room.phase==='running')fail('Game in progress');victim.left=true;}
  if(!active(room).length)room.phase='closed';else if(!member(room,room.hostId))room.hostId=active(room)[0].id;
 }else if(['draft','commit','draw'].includes(action)){
  if(room.phase!=='running')fail('Game not running');const g=restoreGame(room.game);
  if(g.player.id!==actor.id)fail('Not your turn');if(input.turn!==g.turn)fail('Turn changed');
  if(action!=='draw')applyDraft(g,input.draft);
  if(action==='commit'){const result=g.commit();room.message=actor.name+' 님이 '+result.played+'장을 놓았습니다.';finishOrAdvance(room,g,now);}
  else if(action==='draw'){g.draw();room.message=actor.name+' 님이 1장을 먹었습니다.';finishOrAdvance(room,g,now);}
  else room.game=gameState(g);
 }else fail('Invalid action');
 const current=member(room,actor.id);if(current)current.seen=now;touch(room,now);
}
function roomView(room,userId,now=Date.now()){
 if(!member(room,userId))fail('Room membership required');
 const g=room.game&&restoreGame(room.game),self=g?.players.find(p=>p.id===userId),ownTurn=g?.player.id===userId;
 return {id:room.id,viewerId:userId,code:room.code,hostId:room.hostId,capacity:room.capacity,bet:room.bet,outcome:copy(room.outcome),phase:room.phase,revision:room.revision,round:room.round,serverTime:now,startAt:room.startAt,deadline:room.deadline,finishedAt:room.finishedAt,message:room.message,
  members:active(room).map(m=>({id:m.id,name:m.name,ready:m.ready})),
  game:g?{turn:g.turn,currentId:g.player.id,table:copy(g.draft.table),baseTable:copy(g.original.table),rack:ownTurn?[...g.draft.rack]:[...self.rack],baseRack:ownTurn?[...g.original.rack]:[...self.rack],poolCount:g.pool.length,opened:self.opened,nextGroup:g.nextGroup,
   players:g.players.map(p=>({id:p.id,name:p.name,opened:p.opened,count:p.id===g.player.id?g.draft.rack.length:p.rack.length,forfeited:!!p.forfeited})),starterDraw:copy(g.starterDraw),result:copy(g.result)}:null};
}
function roomListing(room){return {id:room.id,code:room.code,capacity:room.capacity,bet:room.bet,count:active(room).length,host:member(room,room.hostId)?.name||'방장',phase:room.phase};}


// server/edge-source.ts
import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
Deno.serve(async request=>{
 const origin=request.headers.get('Origin')||'',allowed=(Deno.env.get('ALLOWED_ORIGINS')||'https://yabol.co.kr,https://www.yabol.co.kr').split(',').map(s=>s.trim());
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
 const respond=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(!allowed.includes(origin))return respond({error:'Origin denied'},403);
 Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'});
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return respond({error:'Invalid method'},405);
 try{
  const authorization=request.headers.get('Authorization')||'';if(!authorization.startsWith('Bearer '))return respond({error:'Approved member required'},401);
  const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const client=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}}),auth=await client.auth.getUser();
  if(auth.error||!auth.data.user)return respond({error:'Approved member required'},401);
  const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}}),user=auth.data.user.id;
  const actorResult=await service.rpc('rummikub_actor',{p_user:user});if(actorResult.error||!actorResult.data)return respond({error:'Approved member required'},403);const actor=actorResult.data;
  const text=await request.text();if(text.length>30000)return respond({error:'Invalid request'},400);let body;try{body=JSON.parse(text);}catch{return respond({error:'Invalid request'},400);}
  const actions=['list','leaderboard','create','join','get','ready','settings','draft','commit','draw','leave','kick'];if(!actions.includes(body?.action))return respond({error:'Invalid action'},400);
  if(body.action==='leaderboard'){const result=await service.rpc('rummikub_leaderboard',{p_user:user});if(result.error)throw Error('Service unavailable');return respond({leaderboard:result.data});}
  if(body.action==='list'){const result=await service.rpc('rummikub_list',{p_user:user});if(result.error)throw Error('Service unavailable');return respond({rooms:result.data.map(roomListing)});}
  if(body.action==='create'){
   for(let retry=0;retry<3;retry++){const room=createRoom(actor,body),result=await service.rpc('rummikub_create',{p_user:user,p_state:room});if(!result.error)return respond({room:roomView(room,user)});if(result.error.code==='23505')continue;if(result.error.message.includes('limit'))return respond({error:'Room limit exceeded'},429);throw Error('Service unavailable');}
   return respond({error:'Service unavailable'},503);
  }
  if(body.action==='join'?!/^[a-f0-9]{6}$/i.test(body.code||''):!uuid.test(body.roomId||''))return respond({error:'Invalid room'},400);
  for(let retry=0;retry<4;retry++){
   const read=await service.rpc('rummikub_read',{p_user:user,p_room:body.action==='join'?null:body.roomId,p_code:body.action==='join'?body.code:null});
   if(read.error||!read.data)return respond({error:'Room not found'},404);
   const before=JSON.stringify(read.data.state),now=Date.now(),base=read.data.state;settleRoom(base,now);let room=structuredClone(base),failure=null;
   try{actRoom(room,actor,body.action,body,now);}catch(error){failure=error;room=base;}
   if(JSON.stringify(room)!==before){
    const save=await service.rpc('rummikub_store',{p_user:user,p_room:read.data.id,p_version:read.data.version,p_state:room});if(save.error)throw Error('Service unavailable');if(!save.data)continue;
   }
   let view;try{view=roomView(room,user,now);}catch{}
   if(failure)return respond({error:failure.message,room:view},409);
   return respond(body.action==='leave'?{left:true}:{room:view});
  }
  return respond({error:'경기 상태가 바뀌었습니다. 다시 시도해 주세요.'},409);
 }catch(error){return respond({error:/^[A-Za-z ]+$/.test(error?.message||'')?error.message:'Service unavailable'},503);}
});
