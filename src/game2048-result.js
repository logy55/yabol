import{createRandom,validTile,hasMoves}from'../dist/game2048/core.js';
export function validate2048Result(seed,input){
 if(!Number.isSafeInteger(seed)||seed<0||seed>4294967295||!Array.isArray(input?.board)||input.board.length!==16||!input.board.every(value=>value===0||validTile(value))||!Number.isSafeInteger(input.moves)||input.moves<1||input.moves>50000||!Number.isSafeInteger(input.score)||input.score<0||input.score>2000000000||!['milestone','over'].includes(input.kind))throw Error('Invalid result');
 const random=createRandom(seed),spawns=input.moves+2;let fours=0;
 for(let i=0;i<spawns;i++){random();if(random()>=.9)fours++;}
 const mass=input.board.reduce((sum,value)=>sum+value,0),energy=input.board.reduce((sum,value)=>sum+(value?value*(Math.log2(value)-1):0),0),filled=input.board.filter(Boolean).length,maxTile=Math.max(...input.board),score=energy-4*fours,merges=spawns-filled;
 if(mass!==2*(spawns+fours)||filled<2||filled>16||merges<0||score!==input.score||input.kind==='over'&&hasMoves(input.board)||input.kind==='milestone'&&maxTile<2048)throw Error('Inconsistent result');
 return{score,moves:input.moves,merges,maxTile,kind:input.kind};
}
