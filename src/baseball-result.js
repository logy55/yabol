import{BALLS,createBallRandom}from'../dist/baseball/game-core.js';
// Lightweight consistency checks, without replaying physics or accepting a
// client-written database score. Authentication, ownership and time remain server-side.
export function validateRoundResult(seed,snapshot,physicsVersion=4){
  const integer=(value,max)=>Number.isSafeInteger(value)&&value>=0&&value<=max;
  if(!integer(seed,4294967295)||![1,2,3,4].includes(physicsVersion)||snapshot?.kind!=='result-snapshot')throw Error('Invalid result snapshot');
  const{frames,score,maxLevel,drops,merges,mergeCounts,ballCounts}=snapshot,n=BALLS.length;
  if(!integer(frames,216000)||!integer(score,2000000)||!integer(maxLevel,n-1)||!integer(drops,6000)||!integer(merges,12000)||frames<Math.max(0,drops-1)*41)throw Error('Invalid result values');
  if(!Array.isArray(mergeCounts)||!Array.isArray(ballCounts)||mergeCounts.length!==n||ballCounts.length!==n||![...mergeCounts,...ballCounts].every(value=>integer(value,6000)))throw Error('Invalid ball counts');
  const random=createBallRandom(seed),dropped=Array(n).fill(0);
  for(let i=0;i<drops;i++){const value=random();dropped[value<.28?0:value<.56?1:value<.79?2:value<.96?3:4]++;}
  let earned=0,total=0,largest=0;
  for(let level=0;level<n;level++){
    const available=dropped[level]+(level?mergeCounts[level-1]:0),remaining=available-2*mergeCounts[level];
    if(remaining<0||remaining!==ballCounts[level])throw Error('Inconsistent ball inventory');
    if(available)largest=level;
    const next=level+1;earned+=mergeCounts[level]*(next<n?(next+1)*(next+2)/2:500);total+=mergeCounts[level];
  }
  if(earned!==score||total!==merges||largest!==maxLevel)throw Error('Inconsistent result totals');
  return{score:earned,maxLevel:largest,drops,merges:total,frames};
}
