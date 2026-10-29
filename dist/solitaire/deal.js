import{Klondike}from'./core.js?v=20261029-solitaire-play';
import{positionKey,sourceForCard}from'./strategy.js?v=20261029-solitaire-play';
export function createDealFromSolution({seed,steps}){
 const game=new Klondike(seed),replay=new Klondike(seed),hints=new Map();
 for(let i=0;i<steps.length;i+=2){const hint=steps[i]===52?{kind:'draw'}:{source:sourceForCard(replay,steps[i]),target:steps[i+1]<7?{kind:'tableau',pile:steps[i+1]}:{kind:'foundation',pile:steps[i+1]-7}};hints.set(positionKey(replay),hint);if(!(hint.kind==='draw'?replay.draw():replay.move(hint.source,hint.target)))throw Error('Invalid Solitaire solution');replay.history=[];}
 if(!replay.won)throw Error('Incomplete Solitaire solution');game.solutionHints=hints;return game;
}
export function prepareSolitaireDeal(seed,{signal}={}){
 return new Promise((resolve,reject)=>{
  if(signal?.aborted){reject(new DOMException('Aborted','AbortError'));return;}const worker=new Worker(new URL('./deal-worker.js?v=20261029-solitaire-play',import.meta.url),{type:'module'});
  const cleanup=()=>{worker.terminate();signal?.removeEventListener('abort',abort);},fail=error=>{cleanup();reject(error);},abort=()=>fail(new DOMException('Aborted','AbortError'));
  signal?.addEventListener('abort',abort,{once:true});worker.onerror=()=>fail(Error('Could not prepare Solitaire deal'));worker.onmessage=({data})=>{cleanup();if(data.error){reject(Error(data.error));return;}try{resolve(createDealFromSolution(data.result));}catch(error){reject(error);}};worker.postMessage({seed});
 });
}
