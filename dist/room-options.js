export const roomMaps=Object.freeze(['운명의 수레바퀴','버블 팝','욕망의 항아리','밤을 달리다']);
export const roomBets=Object.freeze({
  none:{name:'내기 없음'},
  starbucks:{name:'스타벅스 아이스 아메리카노',image:'gift-starbucks.png'},
  mgc:{name:'메가커피 아이스 아메리카노',image:'gift-mgc.png'},
  compose:{name:'컴포즈커피 아이스 아메리카노',image:'gift-compose.png'}
});
const getBet=key=>roomBets[key]||roomBets.none;
export function betField(key='none'){
  return `<label class="room-bet-field">내기<select name="bet">${Object.entries(roomBets).map(([value,bet])=>`<option value="${value}" ${value===key?'selected':''}>${bet.name}</option>`).join('')}</select></label>`;
}
export function betBadge(key){
  const bet=getBet(key);
  return `<span class="room-bet-badge">${bet.image?`<img src="./assets/${bet.image}" width="28" height="28" alt="">`:''}<span>${bet.name}</span></span>`;
}
export function betNotice(key){
  const bet=getBet(key);
  return `<div class="room-bet-notice" role="note">${bet.image?`이번 경기에는 <img src="./assets/${bet.image}" width="36" height="36" alt=""><strong>${bet.name}</strong> 내기가 걸려 있습니다.`:'이번 경기는 내기 없이 진행합니다.'}</div>`;
}
export function roomControls(me,phase){
  const terminal=['finished','closed'].includes(phase),exitState=terminal?'':phase==='running'?'running':me?.ready?'ready':'';
  return `<div class="room-ready-bar"><div class="room-control-buttons"><button class="primary" type="button" id="room-ready" aria-pressed="${Boolean(me?.ready)}" ${!me||['running','finished','closed'].includes(phase)?'disabled':''}>${me?.ready?'준비 취소':'준비'}</button><button type="button" class="secondary" id="room-leave" data-exit-state="${exitState}" aria-describedby="room-leave-hint">나가기</button></div><p id="room-leave-hint" class="room-leave-hint" role="status" hidden></p><p id="room-stage" role="status">모두 준비되면 5초 후 시작합니다.</p></div>`;
}
export function explainRoomLeave(root,notify=()=>{}){
  const state=root.querySelector('#room-leave')?.dataset.exitState;
  if(!state)return false;
  const message=state==='running'?'경기 진행 중에는 나갈 수 없습니다. 결과가 나온 뒤 다시 눌러 주세요.':"준비를 해제한 뒤 나갈 수 있습니다.\n'준비 취소'를 먼저 눌러주세요.";
  const hint=root.querySelector('#room-leave-hint');hint.textContent=message;hint.hidden=false;
  notify(message);return true;
}
