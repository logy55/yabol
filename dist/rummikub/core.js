export const COLOURS=['black','blue','red','gold'];
export const COLOUR_NAMES=['검정','파랑','빨강','주황'];
export function tile(id){if(!Number.isInteger(id)||id<0||id>105)throw Error('잘못된 타일입니다.');return id>=104?{id,joker:true,value:0,colour:null}:{id,joker:false,value:id%13+1,colour:Math.floor(id/26)};}
export function tileId(colour,value,copy=0){return colour*26+copy*13+value-1;}
export const tileValue=id=>id>=104?30:tile(id).value;
export function setInfo(ids){
 if(ids.length<3)return{valid:false,message:'3장 이상 필요해요.'};if(ids.length>13||new Set(ids).size!==ids.length)return{valid:false,message:'중복 타일을 확인해 주세요.'};
 const tiles=ids.map(tile),normal=tiles.filter(t=>!t.joker),options=[];
 if(ids.length<=4&&normal.length&&normal.every(t=>t.value===normal[0].value)&&new Set(normal.map(t=>t.colour)).size===normal.length)options.push({valid:true,kind:'group',label:'그룹',score:normal[0].value*ids.length});
 const first=tiles.findIndex(t=>!t.joker);if(first>=0){const start=tiles[first].value-first,colour=tiles[first].colour;if(start>=1&&start+ids.length-1<=13&&tiles.every((t,i)=>t.joker||t.colour===colour&&t.value===start+i))options.push({valid:true,kind:'run',label:'런',score:ids.length*(start*2+ids.length-1)/2});}
 return options.sort((a,b)=>b.score-a.score)[0]||{valid:false,message:'같은 숫자·다른 색, 또는 같은 색·연속 숫자로 놓아 주세요.'};
}
const clone=state=>structuredClone(state),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b),sorted=ids=>[...ids].sort((a,b)=>a-b);
export class TileGame{
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
export function restoreGame(state){return Object.assign(Object.create(TileGame.prototype),structuredClone(state));}
