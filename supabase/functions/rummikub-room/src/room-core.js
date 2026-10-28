import {TileGame,restoreGame,tileValue} from '../../../../dist/rummikub/core.js';
import {betKeys} from '../../../../dist/rummikub/bets.js';
const copy=value=>value===undefined?null:JSON.parse(JSON.stringify(value));
const fail=message=>{throw Error(message);};
const integer=(n,min,max)=>Number.isInteger(n)&&n>=min&&n<=max;
const active=room=>room.members.filter(m=>!m.left);
const member=(room,id)=>room.members.find(m=>m.id===id&&!m.left);
const gameState=g=>copy(g);
const secureRandom=()=>crypto.getRandomValues(new Uint32Array(1))[0]/4294967296;
export function createRoom(actor,{capacity=4,bet='none'}={},now=Date.now()){
 if(!actor?.id||!actor.approved)fail('Approved member required');
 if(!integer(capacity,2,4))fail('Invalid capacity');if(!betKeys.includes(bet))fail('Invalid bet');
 return {id:crypto.randomUUID(),code:crypto.randomUUID().slice(0,6).toUpperCase(),hostId:actor.id,capacity,bet,phase:'waiting',revision:1,createdAt:now,updatedAt:now,startAt:null,deadline:null,finishedAt:null,round:1,game:null,outcome:null,message:'',members:[{id:actor.id,name:actor.name||'회원',ready:false,seen:now,left:false}]};
}
function touch(room,now){room.revision++;room.updatedAt=now;}
function finishOrAdvance(room,g,now){room.game=gameState(g);if(g.over){room.phase='finished';room.deadline=null;room.finishedAt=now;room.outcome=betOutcome(g);}else room.deadline=now+60000;}
export function betOutcome(g,random=secureRandom){
 const lowest=Math.min(...g.result.scores);let candidates=g.players.flatMap((p,i)=>g.result.scores[i]===lowest?[i]:[]),reason='score',draws=[];
 if(candidates.length>1){const max=Math.max(...candidates.map(i=>g.players[i].rack.length));candidates=candidates.filter(i=>g.players[i].rack.length===max);reason='tile-count';}
 if(candidates.length>1){const values=i=>g.players[i].rack.map(tileValue).sort((a,b)=>b-a),compare=(a,b)=>{const x=values(a),y=values(b);for(let i=0;i<x.length;i++)if(x[i]!==y[i])return x[i]-y[i];return 0;};const highest=candidates.reduce((a,b)=>compare(a,b)>=0?a:b);candidates=candidates.filter(i=>compare(i,highest)===0);reason='tile-values';}
 if(candidates.length>1){const bag=Array.from({length:13},(_,i)=>i+1);draws=candidates.map(index=>({index,value:bag.splice(Math.floor(random()*bag.length),1)[0]}));candidates=[draws.reduce((a,b)=>a.value>b.value?a:b).index];reason='draw';}
 return {loserIndex:candidates[0],decidedBy:reason,draws,counts:g.players.map(p=>p.rack.length)};
}
export function settleRoom(room,now=Date.now(),random=secureRandom){
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
export function actRoom(room,actor,action,input={},now=Date.now(),random=secureRandom){
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
export function roomView(room,userId,now=Date.now()){
 if(!member(room,userId))fail('Room membership required');
 const g=room.game&&restoreGame(room.game),self=g?.players.find(p=>p.id===userId),ownTurn=g?.player.id===userId;
 return {id:room.id,viewerId:userId,code:room.code,hostId:room.hostId,capacity:room.capacity,bet:room.bet,outcome:copy(room.outcome),phase:room.phase,revision:room.revision,round:room.round,serverTime:now,startAt:room.startAt,deadline:room.deadline,finishedAt:room.finishedAt,message:room.message,
  members:active(room).map(m=>({id:m.id,name:m.name,ready:m.ready})),
  game:g?{turn:g.turn,currentId:g.player.id,table:copy(g.draft.table),baseTable:copy(g.original.table),rack:ownTurn?[...g.draft.rack]:[...self.rack],baseRack:ownTurn?[...g.original.rack]:[...self.rack],poolCount:g.pool.length,opened:self.opened,nextGroup:g.nextGroup,
   players:g.players.map(p=>({id:p.id,name:p.name,opened:p.opened,count:p.id===g.player.id?g.draft.rack.length:p.rack.length,forfeited:!!p.forfeited})),starterDraw:copy(g.starterDraw),result:copy(g.result)}:null};
}
export function roomListing(room){return {id:room.id,code:room.code,capacity:room.capacity,bet:room.bet,count:active(room).length,host:member(room,room.hostId)?.name||'방장',phase:room.phase};}
