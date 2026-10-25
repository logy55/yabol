// Display contract for the future authenticated, server-owned competition.
// Key by member ID, never by a changeable or non-unique name.
export function memberLeaders(entries){
  const members=new Map();
  for(const row of Array.isArray(entries)?entries:[]){
    if(!row||typeof row.userId!=='string'||!row.userId||typeof row.name!=='string'||!row.name.trim()||!Number.isSafeInteger(row.score)||row.score<=0||!Number.isInteger(row.maxLevel)||row.maxLevel<0||row.maxLevel>10||!Number.isFinite(row.at)||row.at<0||row.at>8640000000000000)continue;
    const value={userId:row.userId,name:row.name.trim(),score:row.score,maxLevel:row.maxLevel,at:row.at},previous=members.get(row.userId);
    if(!previous||value.score>previous.score||(value.score===previous.score&&value.at<previous.at))members.set(value.userId,value);
  }
  return [...members.values()].sort((a,b)=>b.score-a.score||a.at-b.at||a.userId.localeCompare(b.userId)).slice(0,30);
}
