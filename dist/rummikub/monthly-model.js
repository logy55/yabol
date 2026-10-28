export function rankMonth(at=Date.now()){return new Date(at+9*3600000).toISOString().slice(0,7)+'-01';}
export function rankResetsAt(at=Date.now()){const [year,month]=rankMonth(at).split('-').map(Number);return Date.UTC(year,month,1)-9*3600000;}
export const createMonthlyLedger=()=>({month:null,entries:new Map(),scored:new Map()});
function rollover(ledger,now){const month=rankMonth(now);if(ledger.month!==month){ledger.entries.clear();ledger.month=month;}return month;}
export function recordFinishedRoom(ledger,room,now=Date.now()){
 const month=rollover(ledger,now),g=room.game,result=g?.result;
 if(room.phase!=='finished'||!result||(ledger.scored.get(room.id)||0)>=room.round)return false;
 const players=g.players;if(players.length<2||players.length>4||result.scores.length!==players.length||players.some(p=>typeof p.id!=='string'||!p.id)||new Set(players.map(p=>p.id)).size!==players.length||result.scores.some(s=>!Number.isInteger(s)||Math.abs(s)>1000)||result.scores.reduce((a,b)=>a+b,0)!==0||!result.winners.length||new Set(result.winners).size!==result.winners.length||result.winners.some(i=>!Number.isInteger(i)||i<0||i>=players.length)||!Number.isInteger(room.outcome?.loserIndex)||room.outcome.loserIndex<0||room.outcome.loserIndex>=players.length)throw Error('Invalid finished match');
 ledger.scored.set(room.id,room.round);
 if(rankMonth(room.finishedAt??now)!==month)return false;
 players.forEach((p,i)=>{const previous=ledger.entries.get(p.id)||{userId:p.id,name:p.name,wins:0,games:0,lasts:0,score:0};previous.name=p.name;previous.games++;previous.wins+=Number(result.winners.includes(i));previous.lasts+=Number(room.outcome?.loserIndex===i);previous.score+=result.scores[i];ledger.entries.set(p.id,previous);});
 return true;
}
export function compareMonthly(a,b){return b.wins-a.wins||(b.wins*a.games-a.wins*b.games)||b.score-a.score;}
export function monthlyLeaderboard(ledger,userId,now=Date.now()){
 const month=rollover(ledger,now),all=[...ledger.entries.values()].sort((a,b)=>compareMonthly(a,b)||a.name.localeCompare(b.name,'ko')||a.userId.localeCompare(b.userId));let rank=0;
 const rows=all.map((entry,i)=>{if(!i||compareMonthly(entry,all[i-1])!==0)rank=i+1;return{...entry,rank,winRate:Math.round(entry.wins/entry.games*1000)/10};});
 return {month,entries:rows.slice(0,30),personal:rows.find(r=>r.userId===userId)||null,resetsAt:rankResetsAt(now),serverNow:now};
}
