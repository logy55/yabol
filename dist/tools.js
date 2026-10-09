import {renderOnlineLadder} from './ladder-room.js?v=20261010-member-fixes';
import {renderSettlement} from './settlement.js?v=20261010-layout-access';
import {parseNames, settleExpenses, makeLadder, traceLadder, magicNumber} from './tool-logic.js?v=20261010-member-fixes';
import {teams} from './teams.js?v=20261010-member-fixes';
const escape = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const money = value => `${value.toLocaleString('ko-KR')}원`;

export async function renderTool(main, key, context={}) {
  if (key === 'ladder') await renderOnlineLadder(main,context);
  else if (key === 'settlement') renderSettlement(main,context);
  else if (key === 'magic-number') renderMagicNumber(main);
  else main.innerHTML = '<div class="empty"><strong>도구를 찾을 수 없어요.</strong><a href="#/">홈으로</a></div>';
}
function renderMagicNumber(main) {
  const options = '<option value="">구단 선택</option>'+teams.map(team=>`<option value="${team.id}">${team.name}</option>`).join('');
  const record = (prefix,title) => `<fieldset class="magic-team"><legend>${title}</legend><label>구단<select name="${prefix}Team" required>${options}</select></label><div class="magic-record">${[['Wins','승'],['Losses','패'],['Draws','무']].map(([key,label])=>`<label>${label}<input name="${prefix}${key}" type="number" min="0" max="200" step="1" ${key==='Draws'?'value="0"':''} required></label>`).join('')}</div></fieldset>`;
  main.innerHTML=`<section class="tool-page"><h1>매직넘버 계산기</h1><p class="tool-intro">우리 팀이 경쟁팀보다 높은 승률을 확정하는 데 필요한 승리와 상대 패배 합계를 계산합니다.</p><form id="magic-form" class="tool-card"><label class="magic-season">팀당 시즌 경기 수<input name="total" type="number" min="1" max="200" step="1" value="144" required></label><div class="tool-fields">${record('leader','우리 팀')}${record('rival','경쟁팀')}</div><p class="form-note">현재 성적을 입력해 주세요. 남은 경기에는 무승부가 없다고 가정하고, 같은 승률은 확정으로 처리하지 않습니다. 우승 여부는 다른 경쟁팀에 대해서도 확인해야 합니다.</p><p class="form-error" id="magic-error" role="alert"></p><div class="form-actions"><button type="submit" class="primary">계산하기</button></div></form><div id="magic-result" class="tool-result" aria-live="polite"></div></section>`;
  const form=main.querySelector('#magic-form'),result=main.querySelector('#magic-result'),error=main.querySelector('#magic-error');
  form.addEventListener('input',()=>{result.innerHTML='';error.textContent='';});
  form.onsubmit=event=>{
    event.preventDefault();error.textContent='';result.innerHTML='';
    try{
      const values=new FormData(form);
      if(values.get('leaderTeam')===values.get('rivalTeam'))throw new Error('서로 다른 구단을 선택해 주세요.');
      const read=prefix=>({wins:Number(values.get(prefix+'Wins')),losses:Number(values.get(prefix+'Losses')),draws:Number(values.get(prefix+'Draws'))});
      const calculated=magicNumber(Number(values.get('total')),read('leader'),read('rival'));
      const team=teams.find(team=>team.id===values.get('leaderTeam')),rival=teams.find(team=>team.id===values.get('rivalTeam'));
      result.innerHTML=`<h2>${escape(team.name)} · ${escape(rival.name)} 비교</h2><div class="magic-summary"><span>승률 기준 매직넘버</span><strong>${calculated.number===null?'—':calculated.number}</strong><p>${calculated.number===null?'남은 경기에서 모든 유리한 결과가 나와도 높은 승률을 확정할 수 없어요.':calculated.number===0?'이미 상대의 가능한 최종 승률보다 높아요.':`우리 팀 승리와 경쟁팀 패배의 합계가 <b>${calculated.number}</b>에 도달하면 승률 우위를 확정합니다.`}</p></div><p class="tool-total">남은 경기: ${escape(team.name)} ${calculated.leaderRemaining}경기 · ${escape(rival.name)} ${calculated.rivalRemaining}경기</p><p class="form-note">추가 무승부가 생기면 다시 계산해 주세요. 승률 동률 시 순위 결정 규정은 이 계산에 포함하지 않습니다.</p>`;
    }catch(failure){error.textContent=failure.message;}
  };
}
