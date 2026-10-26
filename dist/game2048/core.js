export const SIZE=4,MAX_TILE=131072;
export function createRandom(seed){let state=seed>>>0;return()=>{let t=state=(state+0x6d2b79f5)>>>0;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296;};}
export function validTile(value){return Number.isInteger(value)&&value>=2&&value<=MAX_TILE&&(value&(value-1))===0;}
export function hasMoves(board){if(board.some(value=>value===0))return true;for(let r=0;r<4;r++)for(let c=0;c<4;c++){const i=r*4+c;if(board[i]<MAX_TILE&&(c<3&&board[i]===board[i+1]||r<3&&board[i]===board[i+4]))return true;}return false;}
export function slide(board,direction){
 if(!['left','right','up','down'].includes(direction))return null;
 const next=Array(16).fill(0),paths=[],mergedCells=[];let score=0,merges=0;
 for(let line=0;line<4;line++){
  const indexes=Array.from({length:4},(_,i)=>direction==='left'?line*4+i:direction==='right'?line*4+3-i:direction==='up'?i*4+line:(3-i)*4+line),filled=indexes.filter(i=>board[i]);let target=0;
  for(let j=0;j<filled.length;j++){
   const from=filled[j],to=indexes[target++],value=board[from];
   if(j+1<filled.length&&value===board[filled[j+1]]&&value<MAX_TILE){next[to]=value*2;paths.push({from,to},{from:filled[++j],to});score+=value*2;merges++;mergedCells.push(to);}else{next[to]=value;paths.push({from,to});}
  }
 }
 if(next.every((value,i)=>value===board[i]))return null;
 return{board:next,paths,score,merges,mergedCells};
}
export class Game2048{
 constructor(seed){this.random=createRandom(seed);this.board=Array(16).fill(0);this.score=0;this.moves=0;this.merges=0;this.won=false;this.over=false;this.spawn();this.spawn();}
 spawn(){const empty=this.board.flatMap((value,i)=>value?[]:[i]);if(!empty.length)return-1;const index=empty[Math.floor(this.random()*empty.length)],value=this.random()<.9?2:4;this.board[index]=value;return index;}
 move(direction){if(this.over)return null;const plan=slide(this.board,direction);if(!plan)return null;this.board=plan.board;this.score+=plan.score;this.merges+=plan.merges;this.moves++;const spawned=this.spawn(),maxTile=Math.max(...this.board),wonNow=!this.won&&maxTile>=2048;this.won ||=wonNow;this.over=!hasMoves(this.board);return{...plan,spawned,wonNow,maxTile,over:this.over};}
 snapshot(runId,kind){return{runId,kind,board:[...this.board],score:this.score,moves:this.moves};}
}
