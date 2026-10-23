import {ladderRoundView} from './ladder-board.js?v=20261024-game-replay';
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const SLOT_MS=4000,TRACE_MS=2800;
const formatTime=ms=>`${Math.floor(ms/60000)}:${String(Math.floor(ms/1000)%60).padStart(2,'0')}`;

export function gameReplaySnapshot(game,room,movie=null){
  if(!['ladder','marble'].includes(game)||room?.phase!=='finished'||!room.round)throw Error('Finished game required');
  const round=structuredClone(room.round),count=round.players?.length;
  if(!Number.isInteger(count)||count<2||count>12||!round.players.every(p=>typeof p.name==='string')||round.outcomes?.length!==count)throw Error('Invalid replay');
  const duration=game==='ladder'?count*SLOT_MS:room.playback_version===2?(room.playback_duration_ms||movie?.duration*1000):Date.parse(room.finish_at)-Date.parse(room.start_at);
  if(!Number.isFinite(duration)||duration<=0||game==='marble'&&!movie)throw Error('Invalid replay duration');
  return {game,roomId:room.id,roundNumber:room.round_number||1,round,movie,duration,bet:room.bet_type||'none',map:room.map_index??0};
}

export function openGameReplay(snapshot,{signal,marblePlayer,onClose=()=>{}}={}){
  if(signal?.aborted)throw Error('Replay cancelled');
  if(snapshot.game==='marble'&&typeof marblePlayer!=='function')throw Error('Marble player required');
  const dialog=document.createElement('dialog'),trigger=document.activeElement;
  dialog.className='dialog game-replay-dialog';dialog.setAttribute('aria-labelledby','game-replay-title');
  const label=snapshot.game==='ladder'?'사다리 게임':'마블룰렛';
  dialog.innerHTML=`<div class="dialog-top"><h2 id="game-replay-title">${label} 리플레이</h2><button type="button" class="icon-button" data-replay-close aria-label="리플레이 닫기">×</button></div><div class="game-replay-board"></div><div class="game-replay-controls"><div class="game-replay-control-row"><button class="primary" type="button" data-replay-play>일시정지</button><button class="secondary" type="button" data-replay-restart>처음부터</button><label>속도<select data-replay-speed aria-label="리플레이 재생 속도"><option value="0.5">0.5배</option><option value="1" selected>1배</option><option value="2">2배</option></select></label></div><div class="game-replay-progress"><input type="range" min="0" max="1000" step="1" value="0" aria-label="리플레이 재생 위치" data-replay-seek><output data-replay-time></output></div><div class="game-replay-save-row"><button class="secondary" type="button" data-replay-save>리플레이 저장</button><button class="text-button" type="button" data-replay-save-cancel hidden>취소</button><span role="status" data-replay-save-status></span></div><p class="sr-only" role="status" data-replay-status>리플레이를 재생합니다.</p></div>`;
  const board=dialog.querySelector('.game-replay-board'),play=dialog.querySelector('[data-replay-play]'),seek=dialog.querySelector('[data-replay-seek]'),time=dialog.querySelector('[data-replay-time]'),status=dialog.querySelector('[data-replay-status]');
  const round=snapshot.round;let disposed=false,playing=true,speed=1,base=0,started=performance.now(),raf=0,stopMarble=()=>{},ladder=null,exportAbort=null,savedUrl=null;
  if(snapshot.game==='ladder'){
    ladder=ladderRoundView(round,Math.min(930,Math.max(360,innerWidth-90)));
    board.innerHTML=ladder.html;
    ladder.paths=ladder.lanes.map((lane,column)=>{const path=board.querySelector(`[data-ladder-path="${column}"]`);return{path,length:path.getTotalLength(),ball:board.querySelector(`[data-ladder-ball="${column}"]`),chip:board.querySelector(`[data-name-column="${column}"]`),slot:board.querySelector(`[data-slot="${lane.end}"]`),slotChip:board.querySelector(`[data-slot-chip="${lane.end}"]`),label:round.outcomes[round.slots[lane.end]],progress:-1};});
  }else board.innerHTML=`<canvas class="marble-canvas" aria-label="방금 끝난 마블룰렛 경기 리플레이"></canvas>`;
  const elapsed=()=>Math.max(0,Math.min(snapshot.duration,base+(playing?(performance.now()-started)*speed:0)));
  function paintLadder(ms){if(!ladder)return;for(const [column,item]of ladder.paths.entries()){
    const progress=Math.max(0,Math.min(1,(ms-column*SLOT_MS)/TRACE_MS));
    if(progress!==item.progress){const point=item.path.getPointAtLength(item.length*progress);item.path.style.strokeDashoffset=String(1-progress);item.ball.setAttribute('transform',`translate(${point.x} ${point.y}) rotate(${progress*1080})`);item.progress=progress;}
    item.ball.style.opacity=ms>=column*SLOT_MS&&progress<1?'1':'0';item.chip.dataset.active=String(Math.floor(ms/SLOT_MS)===column);
    const visible=ms>=column*SLOT_MS+TRACE_MS;item.slot.textContent=visible?item.label:'?';
    if(visible){const outcome=item.label==='꽝'?'lose':'pass';item.slot.dataset.outcome=outcome;item.slotChip.dataset.outcome=outcome;}else{delete item.slot.dataset.outcome;delete item.slotChip.dataset.outcome;}
  }}
  function paintMarble(){if(snapshot.game!=='marble'||disposed)return;stopMarble();stopMarble=marblePlayer(board.querySelector('canvas'),snapshot.movie,round,()=>elapsed()/snapshot.duration,()=>{});if(!playing)stopMarble();}
  function update(){const ms=elapsed();paintLadder(ms);seek.value=String(Math.round(ms/snapshot.duration*1000));seek.setAttribute('aria-valuetext',`${formatTime(ms)} / ${formatTime(snapshot.duration)}`);time.textContent=`${formatTime(ms)} / ${formatTime(snapshot.duration)}`;play.textContent=playing?'일시정지':ms>=snapshot.duration?'다시 재생':'재생';}
  function frame(){if(disposed)return;if(playing&&elapsed()>=snapshot.duration){base=snapshot.duration;playing=false;paintMarble();status.textContent='리플레이가 끝났습니다.';}update();if(playing)raf=requestAnimationFrame(frame);}
  function setPlayback(ms,nextPlaying){base=Math.max(0,Math.min(snapshot.duration,ms));playing=nextPlaying;started=performance.now();cancelAnimationFrame(raf);paintMarble();frame();}
  play.onclick=()=>{const ms=elapsed();setPlayback(ms>=snapshot.duration?0:ms,!playing);status.textContent=playing?'리플레이를 재생합니다.':'리플레이를 일시정지했습니다.';};
  dialog.querySelector('[data-replay-restart]').onclick=()=>{setPlayback(0,true);status.textContent='처음부터 다시 재생합니다.';};
  dialog.querySelector('[data-replay-speed]').onchange=event=>{const ms=elapsed();speed=Number(event.target.value);setPlayback(ms,playing);};
  seek.oninput=()=>setPlayback(Number(seek.value)/1000*snapshot.duration,playing);
  const saveButton=dialog.querySelector('[data-replay-save]'),saveCancel=dialog.querySelector('[data-replay-save-cancel]'),saveStatus=dialog.querySelector('[data-replay-save-status]');
  const download=()=>{const link=document.createElement('a');link.href=savedUrl;link.download=`yabol-${snapshot.game}-replay-${new Date().toISOString().replace(/[:.]/g,'-')}.mp4`;document.body.append(link);link.click();link.remove();};
  saveCancel.onclick=()=>exportAbort?.abort();
  saveButton.onclick=async()=>{
    if(exportAbort)return;if(savedUrl){download();return;}setPlayback(elapsed(),false);
    const control=new AbortController();exportAbort=control;saveButton.disabled=true;saveCancel.hidden=false;saveStatus.textContent='영상을 만드는 중… 0%';
    const inputs=[play,dialog.querySelector('[data-replay-restart]'),dialog.querySelector('[data-replay-speed]'),seek];for(const input of inputs)input.disabled=true;
    try{
      const{exportGameReplay}=await import('./game-replay-export.js?v=20261024-game-replay');
      if(control.signal.aborted||disposed)return;
      const blob=await exportGameReplay(snapshot,{ladder,marblePlayer,signal:control.signal,onProgress:value=>{if(!disposed)saveStatus.textContent=`영상을 만드는 중… ${value}%`;}});
      if(control.signal.aborted||disposed)return;savedUrl=URL.createObjectURL(blob);saveStatus.textContent='영상이 준비되었습니다.';download();
    }catch(error){if(!disposed)saveStatus.textContent=control.signal.aborted?'저장을 취소했습니다.':error?.message==='MP4_UNSUPPORTED'?'이 브라우저는 영상 저장을 지원하지 않습니다. 최신 Chrome 또는 Safari에서 이용해 주세요.':'영상을 저장하지 못했습니다. 다시 시도해 주세요.';}
    finally{if(!disposed){exportAbort=null;saveButton.disabled=false;saveCancel.hidden=true;for(const input of inputs)input.disabled=false;}}
  };
  const onVisibility=()=>{if(document.hidden&&playing)setPlayback(elapsed(),false);};
  function close(restoreFocus=true){if(disposed)return;disposed=true;exportAbort?.abort();if(savedUrl)URL.revokeObjectURL(savedUrl);cancelAnimationFrame(raf);stopMarble();document.removeEventListener('visibilitychange',onVisibility);signal?.removeEventListener('abort',abort);if(dialog.open)dialog.close();dialog.remove();onClose();if(restoreFocus&&trigger?.isConnected)trigger.focus();}
  const abort=()=>close(false);dialog.querySelector('[data-replay-close]').onclick=()=>close();dialog.addEventListener('cancel',event=>{event.preventDefault();close();});dialog.addEventListener('close',()=>close());
  signal?.addEventListener('abort',abort,{once:true});document.addEventListener('visibilitychange',onVisibility);
  document.body.append(dialog);dialog.showModal();started=performance.now();paintMarble();frame();
  return {close};
}

export function createRoomReplaySession({signal,onRematch=()=>{},onClosed=()=>{}}={}){
  let view=null,key=null,ticket=0;
  return {
    open(snapshot,options={}){view?.close(false);const id=++ticket;key={room:snapshot.roomId,round:snapshot.roundNumber};view=openGameReplay(snapshot,{...options,signal,onClose:()=>{if(ticket===id){view=null;key=null;}}});},
    update(room){if(!view)return false;const next=room.round_number||1;if(room.id===key.room&&next===key.round&&room.phase!=='closed'&&room.start_at)return false;const rematch=room.id===key.room&&next>key.round&&room.phase==='waiting';view.close(false);if(rematch)onRematch();else onClosed();return rematch;},
    close(){view?.close(false);}
  };
}
