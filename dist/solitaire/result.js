export const SCORE_RULES={foundation:10,waste:5,flip:5,return:15,recycle:20,undo:5,win:500};
export function solitaireScore(stats,won=false){return Math.max(0,stats.foundation*10+stats.waste*5+stats.flips*5-stats.returns*15-stats.recycles*20-stats.undos*5+(won?500:0));}
export function validateSolitaireResult(input){
 const s=input?.stats;if(!s||!['foundation','waste','flips','returns','recycles','undos'].every(k=>Number.isSafeInteger(s[k])&&s[k]>=0&&s[k]<=10000))throw Error('Invalid counters');
 if(s.flips!==21||s.waste>24||s.foundation!==52+s.returns)throw Error('Invalid completed game');
 if(!Array.isArray(input.foundations)||input.foundations.length!==4||!input.foundations.every((pile,suit)=>Array.isArray(pile)&&pile.length===13&&pile.every((id,rank)=>id===suit*13+rank)))throw Error('Game not completed');
 if(!Number.isSafeInteger(input.moves)||input.moves<52+s.returns*2||input.moves>20000||input.moves<s.recycles+s.undos)throw Error('Invalid move count');
 if(!Number.isSafeInteger(input.elapsedMs)||input.elapsedMs<1000||input.elapsedMs>86400000||input.moves>input.elapsedMs/30+8)throw Error('Invalid duration');
 const score=solitaireScore(s,true);if(input.score!==score)throw Error('Invalid score');
 return{score,elapsedMs:input.elapsedMs,moves:input.moves};
}
