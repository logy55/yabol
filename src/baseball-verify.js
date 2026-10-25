import Matter from './vendor/matter.cjs';
import {BallGame,createBallRandom,WIDTH} from '../dist/baseball/game-core.js';
import{saveBaseballCheckpoint,restoreBaseballCheckpoint}from'./baseball-checkpoint.js';
export function verifyBaseballRun(seed,inputs,frames,physicsVersion=2){
  validateBaseballInputs(seed,inputs,frames);
  const chunk=verifyBaseballChunk(seed,inputs,frames,physicsVersion,null,{maxSteps:216001,budgetMs:Infinity});
  if(!chunk.done)throw Error('Incomplete replay');return chunk.result;
}
export function validateBaseballInputs(seed,inputs,frames){
  if(!Number.isSafeInteger(seed)||seed<0||seed>4294967295||!Number.isSafeInteger(frames)||frames<0||frames>216000||!Array.isArray(inputs)||inputs.length>6000)throw Error('Invalid run');
  let previous=-1;
  for(const input of inputs){
    if(!input||!Number.isSafeInteger(input.frame)||input.frame<0||input.frame>frames||input.frame<=previous||!Number.isFinite(input.x)||input.x<0||input.x>WIDTH)throw Error('Invalid inputs');
    previous=input.frame;
  }
}
export function verifyBaseballChunk(seed,inputs,frames,physicsVersion=2,snapshot=null,{maxSteps=1800,budgetMs=120}={}){
  let game,index=0;
  if(snapshot){({game,inputIndex:index}=restoreBaseballCheckpoint(Matter,seed,snapshot,physicsVersion));}
  else game=new BallGame(Matter,{physicsVersion,random:createBallRandom(seed)});
  const started=performance.now();let steps=0;
  try{
    while(game.frame<=frames){
      if(index<inputs.length&&inputs[index].frame===game.frame){if(!game.drop(inputs[index].x))throw Error('Invalid drop');index++;}
      if(game.frame===frames){if(index!==inputs.length)throw Error('Missing inputs');return{done:true,result:{score:game.score,maxLevel:game.maxLevel,drops:game.drops,merges:game.merges,frames:game.frame,status:game.status},frame:game.frame};}
      if(game.status!=='playing')throw Error('Game already ended');game.step();steps++;
      // Checkpoints are before the next frame's input; it must not be consumed twice.
      if(game.frame<frames&&(steps>=maxSteps||performance.now()-started>=budgetMs))return{done:false,state:saveBaseballCheckpoint(game,index),frame:game.frame};
    }
  }finally{game.dispose();}
}
