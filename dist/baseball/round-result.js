export function recordRoundMerge(counts,event){
  const parent=event.cleared?counts.length-1:event.level-1;
  if(!Number.isInteger(parent)||parent<0||parent>=counts.length)throw Error('Invalid merge result');
  counts[parent]++;
}
export function makeRoundResult(game,runId,mergeCounts){
  const ballCounts=mergeCounts.map(()=>0);
  for(const body of game.balls)if(!body.plugin.ball.dead)ballCounts[body.plugin.ball.level]++;
  return{kind:'result-snapshot',runId,frames:game.frame,score:game.score,maxLevel:game.maxLevel,drops:game.drops,merges:game.merges,mergeCounts:[...mergeCounts],ballCounts};
}
export function isRoundResult(value){return value?.kind==='result-snapshot'&&Array.isArray(value.mergeCounts)&&Array.isArray(value.ballCounts);}
