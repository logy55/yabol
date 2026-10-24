import Matter from './baseball/matter.js';
import {BallGame,BALLS,WIDTH,HEIGHT,FLOOR,DANGER,DROP_Y,createBallRandom} from './baseball/game-core.js';
import {createBallArt} from './baseball/ball-art.js';
import {memberLeaders} from './baseball/leaderboard.js';
import {gameMarkup} from './baseball/markup.js';
let sharedArt,sharedBackground;
export async function renderBaseballGame(main,context={}){
const{db,actor,signal,isCurrent=()=>true}=context,alive=()=>!signal?.aborted&&isCurrent();
if(!alive())return;
if(!db||!actor){main.innerHTML='<div class="empty">로그인 후 이용해 주세요.</div>';return;}
main.innerHTML=gameMarkup;
const root=main.querySelector('.baseball-page');
const scoreStatus=document.createElement('p');scoreStatus.id='score-status';scoreStatus.className='score-status';scoreStatus.hidden=true;scoreStatus.setAttribute('aria-live','polite');root.querySelector('.play-panel').append(scoreStatus);
const $=selector=>root.querySelector(selector),field=$('#field'),scale=Math.min(devicePixelRatio||1,1.75);
field.width=Math.round(WIDTH*scale);field.height=Math.round(HEIGHT*scale);
const ctx=field.getContext('2d',{alpha:false});
const format=n=>new Intl.NumberFormat('ko-KR').format(n),reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
let best=0,runInfo=null,inputs=[],submission=null,submitted=false,resetting=false;
let game,raf=0,last=0,lastPaint=0,accumulator=0,particles=[],pointer=null,restartResume=false,starting=null;
let dirty=true,uiDirty=false,fieldRect=null,drawBall,icon,background,lastNext=-1,lastStatus='';
const launch=document.createElement('section');launch.className='baseball-launch';launch.innerHTML='<button id="baseball-open" class="button-primary" type="button">게임 시작</button>';
root.insertBefore(launch,$('.game-layout'));
const gameDialog=document.createElement('dialog');gameDialog.className='baseball-game-dialog';gameDialog.tabIndex=-1;gameDialog.setAttribute('aria-labelledby','baseball-popup-title');
gameDialog.innerHTML='<div class="baseball-popup-heading"><h2 id="baseball-popup-title">야구공 게임</h2><button id="baseball-close" type="button" aria-label="게임 팝업 닫기">닫기 ×</button></div>';
gameDialog.append($('.play-panel'));root.append(gameDialog);
function refreshLauncher(){ $('#baseball-open').textContent=game?.status==='over'?'경기 결과 보기':game?.drops?'게임 계속하기':'게임 시작'; }
function openGame(){if(!gameDialog.open)gameDialog.showModal();document.body.classList.add('baseball-dialog-open');fieldRect=null;gameDialog.focus({preventScroll:true});if(!game){void startGame();return;}if(game.status==='paused')game.resume();dirty=true;wake();}
$('#baseball-open').onclick=openGame;$('#baseball-close').onclick=()=>gameDialog.close();
gameDialog.addEventListener('close',()=>{document.body.classList.remove('baseball-dialog-open');pointer=null;game?.pause();stopLoop();refreshLauncher();void refreshLeaderboard();});

function ranking(entries=[]){
  const records=memberLeaders(entries),body=$('#ranking-body');body.replaceChildren();
  for(const record of records){
    const row=document.createElement('tr'),date=new Intl.DateTimeFormat('ko-KR',{month:'numeric',day:'numeric'}).format(record.at);
    for(const value of [format(record.score),record.name,BALLS[record.maxLevel].name,date]){const cell=document.createElement('td');cell.textContent=value;row.append(cell);}
    body.append(row);
  }
  $('#ranking-empty').textContent='아직 등록된 기록이 없습니다.';$('#ranking-empty').hidden=records.length>0;
}
ranking();

function readout(){uiDirty=true;dirty=true;wake();}
function updateReadout(){
  if(!game||!alive())return;
  refreshLauncher();
  $('#score').textContent=format(game.score);$('#best').textContent=format(best);$('#drops').textContent=game.drops;$('#merges').textContent=game.merges;
  $('#largest').textContent=game.drops||game.merges?BALLS[game.maxLevel].name:'—';
  field.setAttribute('aria-label',`${BALLS[game.current].name}. 공을 놓을 위치를 정하고 클릭하거나 손을 떼세요. 키보드 방향키와 스페이스로도 조작할 수 있습니다.`);
  field.setAttribute('aria-busy',String(game.pendingTurn));
  if(lastNext!==game.next){icon($('#next-icon'),game.next,29);$('#next-icon').setAttribute('aria-label',`다음 공: ${BALLS[game.next].name}`);lastNext=game.next;}
  $('#first-tip').hidden=game.drops>0;
  $('#pause').disabled=game.status==='over';if(lastStatus!==game.status){$('#pause').innerHTML=game.status==='paused'?'<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m7 4 8 6-8 6z"/></svg>계속하기':'<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M7 4v12M13 4v12"/></svg>일시정지';lastStatus=game.status;}
  $('#overlay').hidden=game.status==='playing';
  if(game.status==='over'){$('#overlay-eyebrow').textContent='NICE GAME';$('#overlay-title').textContent='오늘도 나이스 플레이!';$('#overlay-message').textContent=`이번 점수 ${format(game.score)}점\n나의 최고점 ${format(best)}점`;$('#overlay-action').textContent='한 판 더 →';}
  else{$('#overlay-eyebrow').textContent='TIME OUT';$('#overlay-title').textContent='잠깐 쉬는 중';$('#overlay-message').textContent='준비되면 이어서 해요.';$('#overlay-action').textContent='계속하기 →';}
}
function merged(event){
  const count=reduced?0:event.level===10?42:11;
  for(let i=0;i<count;i++){const angle=i*2.399;particles.push({x:event.x,y:event.y,vx:Math.cos(angle)*(1.3+Math.random()*2.8),vy:-1.8-Math.random()*3.2,life:1,colour:event.level===10?'#c3a15d':BALLS[event.level].colour});}
  particles.push({x:event.x,y:event.y-15,vx:0,vy:-.55,life:1.3,text:`+${event.points}`,colour:'#587f68'});
  $('#announcer').textContent=`${BALLS[event.level].name} 합치기 성공! ${event.points}점!`;
}

function prepareArtwork(){
({draw:drawBall,icon}=sharedArt??=createBallArt(BALLS));
if(sharedBackground){background=sharedBackground;return;}
background=document.createElement('canvas');background.width=WIDTH*2;background.height=HEIGHT*2;
const bg=background.getContext('2d');bg.scale(2,2);
const paper=bg.createLinearGradient(0,0,0,HEIGHT);paper.addColorStop(0,'#fcfaf4');paper.addColorStop(1,'#f5f4e9');bg.fillStyle=paper;bg.fillRect(0,0,WIDTH,HEIGHT);
bg.save();bg.strokeStyle='#dce2d444';bg.lineWidth=1;
for(let y=147;y<FLOOR;y+=24){bg.beginPath();bg.moveTo(0,y);bg.lineTo(WIDTH,y);bg.stroke();}
for(let x=4;x<WIDTH;x+=24){bg.beginPath();bg.moveTo(x,140);bg.lineTo(x,FLOOR);bg.stroke();}
bg.restore();
bg.fillStyle='#c6d0b270';bg.fillRect(0,FLOOR,WIDTH,HEIGHT-FLOOR);bg.fillStyle='#acbf9470';bg.fillRect(0,FLOOR,WIDTH,2);
for(let x=0;x<WIDTH;x+=20){bg.fillStyle=x%40?'#b8c5a438':'#d4dcc22b';bg.fillRect(x,FLOOR+3,20,HEIGHT-FLOOR);}
sharedBackground=background;
}

function render(){
  if(!game||!background?.width)return;
  ctx.setTransform(field.width/WIDTH,0,0,field.height/HEIGHT,0,0);ctx.drawImage(background,0,0,WIDTH,HEIGHT);
  const danger=game.overflow>0;ctx.strokeStyle=danger?'#ca7979':'#d4b7ad';ctx.lineWidth=1;ctx.setLineDash([5,6]);ctx.beginPath();ctx.moveTo(13,DANGER);ctx.lineTo(WIDTH-13,DANGER);ctx.stroke();ctx.setLineDash([]);
  if(danger){ctx.fillStyle=`rgba(196,99,99,${.025+.035*Math.sin(performance.now()/150)})`;ctx.fillRect(0,DANGER-20,WIDTH,70);}
  if(game.status==='playing'){
    const r=BALLS[game.current].r;let floor=FLOOR;
    for(const body of game.balls){const def=BALLS[body.plugin.ball.level],rx=def.rx||def.r,ry=def.ry||def.r,dx=Math.abs(body.position.x-game.aim);if(dx<rx)floor=Math.min(floor,body.position.y-ry*Math.sqrt(1-dx*dx/(rx*rx)));}
    ctx.strokeStyle='#aab5bd6b';ctx.setLineDash([3,7]);ctx.beginPath();ctx.moveTo(game.aim,DROP_Y+r+8);ctx.lineTo(game.aim,Math.max(DROP_Y+r+8,floor-r));ctx.stroke();ctx.setLineDash([]);
    if(!game.pendingTurn)drawBall(ctx,game.current,game.aim,DROP_Y,1,0,.94);else{ctx.fillStyle='#a6b0b6';ctx.beginPath();ctx.arc(game.aim,DROP_Y,2.5,0,Math.PI*2);ctx.fill();}
  }
  for(const body of game.balls)drawBall(ctx,body.plugin.ball.level,body.position.x,body.position.y,1,body.angle);
  for(const p of particles){ctx.globalAlpha=Math.max(0,p.life);if(p.text){ctx.font='800 19px NanumSquareRound, sans-serif';ctx.textAlign='center';ctx.lineWidth=4;ctx.strokeStyle='#fcfaf2';ctx.strokeText(p.text,p.x,p.y);ctx.fillStyle=p.colour;ctx.fillText(p.text,p.x,p.y);}else{ctx.fillStyle=p.colour;ctx.beginPath();ctx.arc(p.x,p.y,2.3,0,Math.PI*2);ctx.fill();}}ctx.globalAlpha=1;
}
function stopLoop(){cancelAnimationFrame(raf);raf=0;last=0;accumulator=0;}
function wake(){if(!raf&&game&&gameDialog.open&&!document.hidden&&alive())raf=requestAnimationFrame(frame);}
// Physics stays fixed at 60 Hz. Input and merge callbacks only invalidate one paint.
function frame(now){
  raf=0;if(!game||!gameDialog.open||document.hidden||!alive())return;
  const delta=Math.min(65,last?now-last:16.667);last=now;
  if(game.status==='playing'){
    accumulator+=delta;
    while(accumulator>=1000/60){
      if(game.overflow||game.balls.some(body=>!body.isSleeping))dirty=true;
      game.step(1000/60);accumulator-=1000/60;
    }
    if(particles.length)dirty=true;
    for(const p of particles){p.x+=p.vx*delta/16.667;p.y+=p.vy*delta/16.667;if(!p.text)p.vy+=.075*delta/16.667;p.life-=delta/(p.text?1050:800);}particles=particles.filter(p=>p.life>0);
  }else accumulator=0;
  if(uiDirty){uiDirty=false;updateReadout();}
  if(dirty&&now-lastPaint>=1000/60-.5){dirty=false;lastPaint=now;render();}
  if(game.status==='playing'||dirty||uiDirty)wake();else last=0;
}
const point=event=>{fieldRect??=field.getBoundingClientRect();return(event.clientX-fieldRect.left)/fieldRect.width*WIDTH;};
field.addEventListener('pointerdown',event=>{
  if(game?.status!=='playing'||event.isPrimary===false||event.button&&event.button!==0)return;
  fieldRect=null;pointer={id:event.pointerId};
  game.aimAt(point(event));
  field.setPointerCapture(event.pointerId);if(event.pointerType!=='touch')field.focus({preventScroll:true});event.preventDefault();
  dirty=true;wake();
});
field.addEventListener('pointermove',event=>{
  if(game?.status!=='playing')return;
  if(event.pointerType==='mouse'||pointer?.id===event.pointerId){game.aimAt(point(event));dirty=true;wake();}
});
field.addEventListener('pointerup',event=>{
  if(event.pointerId!==pointer?.id)return;pointer=null;
  if(field.hasPointerCapture(event.pointerId))field.releasePointerCapture(event.pointerId);
  game?.drop(point(event));dirty=true;wake();
});
field.addEventListener('pointercancel',()=>{pointer=null;});
field.addEventListener('lostpointercapture',()=>{pointer=null;});
field.addEventListener('keydown',event=>{if(game?.status==='playing'&&['ArrowLeft','ArrowRight',' ','Enter'].includes(event.key)){event.preventDefault();if(event.key==='ArrowLeft')game.aimAt(game.aim-15);else if(event.key==='ArrowRight')game.aimAt(game.aim+15);else if(!event.repeat)game.drop();dirty=true;wake();}});
async function reset(){
  if(resetting)return;resetting=true;game.status='over';readout();$('#overlay-action').disabled=true;
  try{if(!await submitRound())return;await beginRound();if(alive())field.focus({preventScroll:true});}
  catch{if(alive())showStartError();}
  finally{resetting=false;if(alive())$('#overlay-action').disabled=false;}
}
$('#pause').onclick=()=>{if(game)game.status==='paused'?game.resume():game.pause();};
$('#overlay-action').onclick=()=>{if(game.status==='over')void reset();else game.resume();field.focus({preventScroll:true});};
$('#restart').onclick=()=>{if(!game||starting||resetting)return;if(!game.drops||game.status==='over'){void reset();return;}restartResume=game.status==='playing';game.pause();$('#restart-dialog').showModal();};
$('#restart-cancel').onclick=()=>$('#restart-dialog').close();
$('#restart-confirm').onclick=()=>{restartResume=false;$('#restart-dialog').close();void reset();};
$('#restart-dialog').addEventListener('close',()=>{if(restartResume)game.resume();restartResume=false;});
const visibility=()=>{fieldRect=null;if(document.hidden){game?.pause();stopLoop();}else{if(!gameDialog.open)void refreshLeaderboard();readout();}};
document.addEventListener('visibilitychange',visibility);
const pagehide=()=>{game?.pause();stopLoop();};window.addEventListener('pagehide',pagehide);
const invalidateRect=()=>{fieldRect=null;};window.addEventListener('resize',invalidateRect);gameDialog.addEventListener('scroll',invalidateRect,{passive:true});
const rankingsTimer=setInterval(()=>{if(!document.hidden&&!gameDialog.open)void refreshLeaderboard();},15000);
signal?.addEventListener('abort',()=>{
  stopLoop();clearInterval(rankingsTimer);document.removeEventListener('visibilitychange',visibility);window.removeEventListener('pagehide',pagehide);window.removeEventListener('resize',invalidateRect);
  for(const dialog of root.querySelectorAll('dialog'))if(dialog.open)dialog.close();
  document.body.classList.remove('baseball-dialog-open');game?.pause();void submitRound();game?.dispose();
},{once:true});
void refreshLeaderboard();


async function request(action,fields={}){
  const{data,error}=await db.functions.invoke('baseball-score',{body:{action,...fields}});
  if(error||!data||(action==='start'?!data.run:!data.result))throw Error(data?.code||'연결을 확인해 주세요.');return data;
}
async function refreshLeaderboard(){
  try{const{data,error}=await db.rpc('get_baseball_leaderboard');if(!alive())return;if(error||!data)throw error||Error('Missing ranking');best=Number(data.personalBest)||0;ranking(data.entries);$('#best').textContent=format(best);$('#ranking-empty').classList.remove('ranking-error');readout();}
  catch{if(alive()){$('#ranking-empty').hidden=false;$('#ranking-empty').classList.add('ranking-error');$('#ranking-empty').textContent='랭킹을 불러오지 못했어요. 잠시 뒤 다시 확인해 주세요.';}}
}
function saving(message,retry=false){
  if(!alive())return;const area=$('#score-status');area.replaceChildren();area.hidden=!message;area.append(document.createTextNode(message));
  if(retry){const button=document.createElement('button');button.type='button';button.textContent='다시 저장';button.onclick=()=>void submitRound();area.append(button);}
}
async function submitRound(){
  if(submitted||!runInfo||!game||!inputs.length)return true;if(submission)return submission;
  const snapshot={runId:runInfo.id,frames:game.frame,inputs:inputs.map(input=>({...input}))};
  submission=(async()=>{saving('기록 저장 중…');try{const{result}=await request('finish',snapshot);submitted=true;if(alive()){game.score=result.score;readout();saving('기록을 저장했습니다.');await refreshLeaderboard();}return true;}catch{saving('기록을 저장하지 못했어요.',true);return false;}})();
  try{return await submission;}finally{submission=null;}
}
function showStartError(){
  if(!alive())return;stopLoop();uiDirty=false;$('#overlay').hidden=false;$('#overlay-eyebrow').textContent='';$('#overlay-title').textContent='경기를 준비하지 못했어요.';$('#overlay-message').textContent='잠시 뒤 다시 시도해 주세요.';$('#overlay-action').hidden=false;$('#overlay-action').disabled=false;$('#overlay-action').textContent='다시 시도';$('#overlay-action').onclick=()=>{if(game)void reset();else void startGame();};$('#pause').disabled=true;$('#restart').disabled=true;
}
async function startGame(){if(starting)return starting;starting=beginRound().catch(showStartError).finally(()=>{starting=null;});return starting;}
async function beginRound(){
  $('#overlay').hidden=false;$('#overlay-title').textContent='경기 준비 중';$('#overlay-message').textContent='';$('#overlay-action').hidden=true;$('#pause').disabled=true;$('#restart').disabled=true;
  const response=await request('start');if(!alive())return;
  if(!response.run||typeof response.run.id!=='string'||!Number.isSafeInteger(response.run.seed))throw Error('Invalid run');
  prepareArtwork();game?.dispose();runInfo=response.run;inputs=[];submitted=false;particles=[];last=0;lastPaint=0;lastNext=-1;lastStatus='';accumulator=0;saving('');$('#restart').disabled=false;$('#overlay-action').hidden=false;$('#overlay-action').onclick=()=>{if(game.status==='over')void reset();else game.resume();field.focus({preventScroll:true});};
  game=undefined;game=new BallGame(Matter,{random:createBallRandom(runInfo.seed),onChange:readout,onMerge:merged,onDrop:input=>inputs.push(input),onOver:()=>{$('#announcer').textContent=`게임 종료. ${game.score}점입니다.`;void submitRound();}});if(!gameDialog.open)game.pause();readout();
}

}

