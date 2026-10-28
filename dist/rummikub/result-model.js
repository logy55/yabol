export function roundResult(room){
 const game=room?.game,result=game?.result;
 if(room?.phase!=='finished'||!result||result.scores.length!==game.players.length)throw Error('경기 결과를 아직 받지 못했습니다.');
 const rows=game.players.map((p,index)=>({index,id:p.id,name:p.name,score:result.scores[index],count:room.outcome?.counts[index]??p.count,winner:result.winners.includes(index),last:room.outcome?.loserIndex===index}));
 for(const row of rows)row.rank=row.winner?1:1+rows.filter(other=>other.score>row.score).length;
 for(const row of rows)row.shared=rows.filter(other=>other.rank===row.rank).length>1;
 rows.sort((a,b)=>a.rank-b.rank||b.score-a.score||a.index-b.index);
 return {rows,winners:rows.filter(r=>r.winner),last:rows.find(r=>r.last),shared:rows.some(r=>r.shared),reason:result.reason,round:room.round,bet:room.bet||'none',decidedBy:room.outcome?.decidedBy,draws:room.outcome?.draws||[]};
}
export const tieReason={score:'공식 점수가 가장 낮습니다.','tile-count':'공식 점수가 같아 남은 타일 수로 정했습니다.','tile-values':'점수와 타일 수가 같아 큰 타일부터 차례로 비교했습니다.',draw:'완전 동점으로 동점자끼리 숫자를 추첨했습니다.'};
