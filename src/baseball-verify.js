import Matter from './vendor/matter.cjs';
import {BallGame,createBallRandom,WIDTH} from '../dist/baseball/game-core.js';
export function verifyBaseballRun(seed,inputs,frames,physicsVersion=2){
  if(!Number.isSafeInteger(seed)||seed<0||seed>4294967295||!Number.isSafeInteger(frames)||frames<0||frames>216000||!Array.isArray(inputs)||inputs.length>6000)throw Error('Invalid run');
  let previous=-1;
  for(const input of inputs){
    if(!input||!Number.isSafeInteger(input.frame)||input.frame<0||input.frame>frames||input.frame<=previous||!Number.isFinite(input.x)||input.x<0||input.x>WIDTH)throw Error('Invalid inputs');
    previous=input.frame;
  }
  const game=new BallGame(Matter,{physicsVersion,random:createBallRandom(seed)});let index=0;
  try{
    for(let frame=0;frame<=frames;frame++){
      if(index<inputs.length&&inputs[index].frame===frame){if(!game.drop(inputs[index].x))throw Error('Invalid drop');index++;}
      if(frame<frames){if(game.status!=='playing')throw Error('Game already ended');game.step();}
    }
    if(index!==inputs.length)throw Error('Missing inputs');
    return{score:game.score,maxLevel:game.maxLevel,drops:game.drops,merges:game.merges,frames:game.frame,status:game.status};
  }finally{game.dispose();}
}
