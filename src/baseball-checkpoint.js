import{BallGame,createBallRandom}from'../dist/baseball/game-core.js';
// Preserve object identity, circular references, contact impulses and IEEE values.
// Snapshots are written only by the verifier into the private run table.
function pack(root){
 const ids=new Map(),nodes=[];
 function value(input){
  if(input===undefined)return{u:1};
  if(typeof input==='number'&&(!Number.isFinite(input)||Object.is(input,-0)))return{n:Object.is(input,-0)?'-0':String(input)};
  if(!input||typeof input!=='object'){if(typeof input==='function')throw Error('Unexpected checkpoint callback');return input;}
  if(ids.has(input))return{r:ids.get(input)};
  const id=nodes.length;ids.set(input,id);nodes.push(null);
  nodes[id]=Array.isArray(input)?['a',Array.from(input,value)]:[Object.getPrototypeOf(input)===null?'n':'o',Object.entries(input).filter(([key])=>key!=='events').map(([key,v])=>[key,value(v)])];
  return{r:id};
 }
 const entry=value(root);return{entry,nodes};
}
function unpack(graph){
 const objects=graph.nodes.map(([type])=>type==='a'?[]:type==='n'?Object.create(null):{});
 const value=input=>input&&typeof input==='object'?'r'in input?objects[input.r]:'u'in input?undefined:input.n==='-0'?-0:Number(input.n):input;
 graph.nodes.forEach(([type,props],i)=>{if(type==='a')for(const v of props)objects[i].push(value(v));else for(const[key,v]of props)Object.defineProperty(objects[i],key,{value:value(v),enumerable:true,writable:true,configurable:true});});
 return value(graph.entry);
}
const fields=['physicsVersion','nextBodyId','time','frame','score','merges','drops','maxLevel','status','overflow','nextDrop','pendingTurn','current','next','aim'];
export function saveBaseballCheckpoint(game,inputIndex){
 if(game.queue.length||game.reserved.size||!game.random.getState)throw Error('Checkpoint not at a step boundary');
 return{format:1,inputIndex,rng:game.random.getState(),fields:Object.fromEntries(fields.map(key=>[key,game[key]])),world:pack({engine:game.engine,balls:game.balls,boundaries:game.boundaries})};
}
export function restoreBaseballCheckpoint(Matter,seed,snapshot,physicsVersion){
 if(snapshot?.format!==1||snapshot.fields.physicsVersion!==physicsVersion)throw Error('Invalid checkpoint');
 const random=createBallRandom(seed),game=new BallGame(Matter,{physicsVersion,random});game.dispose();
 const world=unpack(snapshot.world);Object.assign(game,snapshot.fields,world);random.setState(snapshot.rng);game.queue=[];game.reserved=new Set();
 Matter.Events.on(game.engine,'collisionStart collisionActive',event=>game.collisions(event.pairs));return{game,inputIndex:snapshot.inputIndex};
}
