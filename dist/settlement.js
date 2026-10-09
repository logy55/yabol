export function renderSettlement(main,{signal}={}){
  main.innerHTML='<section class="tool-page settlement-page"><div class="board-heading"><div><h1>정산 계산기</h1><p>차수별로 지출과 참여자를 기록하면 최종 송금액을 계산합니다.</p></div></div><iframe class="settlement-frame" src="./settlement.html?v=20261010-community-final" title="차수별 정산 계산기" allow="clipboard-write"></iframe></section>';
  const frame=main.querySelector('.settlement-frame');
  const resize=event=>{if(event.source===frame.contentWindow&&event.origin===location.origin&&event.data?.type==='settlement-height'&&Number.isFinite(event.data.height))frame.style.height=`${Math.max(550,Math.min(20000,event.data.height+8))}px`;};
  window.addEventListener('message',resize);signal?.addEventListener('abort',()=>window.removeEventListener('message',resize),{once:true});
}
