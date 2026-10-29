import{Klondike,seededRandom,suit}from'./core.js?v=20261029-solitaire-play';
import{positionKey}from'./strategy.js?v=20261029-solitaire-play';
// Runs in a worker before play. Only a deal with a complete legal draw-three path is accepted.
export function solveDeal(seed){
 const game=new Klondike(seed),seen=new Set(),steps=[];
 for(let turn=0;turn<750&&!game.won;turn++){
  const key=positionKey(game);if(seen.has(key))return null;seen.add(key);const sources=game.sources();let option=null;
  for(const source of sources){const ids=game.cards(source);if(ids.length===1&&game.canMove(source,{kind:'foundation',pile:suit(ids[0])})){option={source,target:{kind:'foundation',pile:suit(ids[0])}};break;}}
  if(!option){const possibilities=[];for(const source of sources)for(let pile=0;pile<7;pile++){const target={kind:'tableau',pile};if(!game.canMove(source,target)||source.kind==='tableau'&&source.index===0&&!game.tableau[pile].length)continue;const prior=source.kind==='tableau'?game.tableau[source.pile][source.index-1]:null;possibilities.push({source,target,priority:prior&&!prior.up?100:source.kind==='waste'?50:source.index>0?10:1});}possibilities.sort((a,b)=>b.priority-a.priority);option=possibilities.find(o=>{const before=game.state();game.move(o.source,o.target);const fresh=!seen.has(positionKey(game));Object.assign(game,before);game.history.pop();game.moves--;return fresh;});}
  if(option){steps.push(game.cards(option.source)[0],option.target.kind==='foundation'?7+option.target.pile:option.target.pile);game.move(option.source,option.target);}else if(game.stock.length||game.waste.length){game.draw();steps.push(52,0);}else return null;game.history=[];
 }
 return game.won?{seed,steps}:null;
}
export function findSolvableDeal(seed,maxAttempts=1024){const random=seededRandom(seed);for(let attempts=1;attempts<=maxAttempts;attempts++){const candidate=attempts===1?seed:Math.floor(random()*4294967296),solution=solveDeal(candidate);if(solution)return{...solution,attempts};}throw Error('Could not verify a new deal');}
