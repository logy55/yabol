const rank=id=>id%13+1,suit=id=>Math.floor(id/13),red=id=>suit(id)===1||suit(id)===2;
export function positionKey(game,canonical=false){const columns=game.tableau.map(p=>p.map(c=>c.id*2+Number(c.up)).join(','));if(canonical)columns.sort();return game.stock.join(',')+'|'+game.waste.join(',')+'|'+game.foundations.map(p=>p.length).join(',')+'|'+columns.join('|');}
export function sourceForCard(game,id){if(game.waste.at(-1)===id)return{kind:'waste'};for(const[pile,p]of game.tableau.entries()){const index=p.findIndex(c=>c.id===id&&c.up);if(index>=0)return{kind:'tableau',pile,index};}for(const[pile,p]of game.foundations.entries())if(p.at(-1)===id)return{kind:'foundation',pile};return null;}
export function nextFoundation(game){for(const source of game.sources()){const ids=game.cards(source);if(ids.length===1){const target={kind:'foundation',pile:suit(ids[0])};if(game.canMove(source,target))return{source,target};}}return null;}
function safeFoundation(game,id){const r=rank(id);return r<=2||game.foundations.every((p,s)=>s===suit(id)||p.length>=r-(red(s*13)!==red(id)?1:2));}
function fork(game){const copy=Object.create(Object.getPrototypeOf(game));return Object.assign(copy,game.state(),{moves:game.moves,history:[]});}
function hidden(game){return game.tableau.flat().filter(c=>!c.up).length;}
function options(game){const result=[];for(const source of [...game.sources(),...game.foundations.flatMap((p,pile)=>p.length?[{kind:'foundation',pile}]:[])]){const cards=game.cards(source);if(!cards.length)continue;const id=cards[0];if(cards.length===1&&safeFoundation(game,id)){const target={kind:'foundation',pile:suit(id)};if(game.canMove(source,target))result.push({source,target,priority:90});}for(let pile=0;pile<7;pile++){const target={kind:'tableau',pile};if(!game.canMove(source,target)||source.kind==='tableau'&&source.index===0&&!game.tableau[pile].length)continue;const prior=source.kind==='tableau'?game.tableau[source.pile][source.index-1]:null;result.push({source,target,priority:prior&&!prior.up?100:source.kind==='waste'?70:source.kind==='foundation'?-20:10});}}return result.sort((a,b)=>b.priority-a.priority);}
export function helpfulHint(game){
 if(game.won)return null;
 const guided=game.solutionHints?.get(positionKey(game));if(guided)return guided;
 const previous=new Set(game.history.map(s=>positionKey(s,true)));
 const initialHidden=hidden(game),initialWaste=game.waste.length,initialFoundation=game.foundations.flat().length,visited=new Set([positionKey(game,true),...previous]),queue=[{game,first:null,depth:0}];let expanded=0;
 while(queue.length&&expanded++<180){const node=queue.shift();if(node.depth>=3)continue;for(const option of options(node.game)){const copy=fork(node.game);copy.move(option.source,option.target);const key=positionKey(copy,true);if(visited.has(key))continue;visited.add(key);const first=node.first||{source:option.source,target:option.target};if(hidden(copy)<initialHidden||copy.waste.length<initialWaste||copy.foundations.flat().length>initialFoundation||game.solutionHints?.has(positionKey(copy)))return first;queue.push({game:copy,first,depth:node.depth+1});}}
 if(game.stock.length||game.waste.length){const copy=fork(game);copy.draw();if(!previous.has(positionKey(copy,true)))return{kind:'draw'};}
 return null;
}
