export const SIZE=20, START_LENGTH=4, POINTS=10;
const DIRS={up:{x:0,y:-1},down:{x:0,y:1},left:{x:-1,y:0},right:{x:1,y:0}};
export class SnakeGame{
 constructor(seed=1){this.seed=seed>>>0;this.body=Array.from({length:START_LENGTH},(_,i)=>({x:6-i,y:10}));this.previous=this.body.map(p=>({...p}));this.direction='right';this.queue=[];this.food={x:10,y:10};this.eaten=0;this.moves=0;this.over=false;this.reason=null;}
 get score(){return this.eaten*POINTS;}
 get interval(){return Math.max(85,160-this.eaten*2);}
 random(){this.seed=(Math.imul(this.seed,1664525)+1013904223)>>>0;return this.seed/4294967296;}
 turn(direction){const next=DIRS[direction],last=DIRS[this.queue.at(-1)||this.direction];if(!next||this.over||this.queue.length>=2||next.x===last.x&&next.y===last.y||next.x===-last.x&&next.y===-last.y)return false;this.queue.push(direction);return true;}
 step(){if(this.over)return {over:true};this.previous=this.body.map(p=>({...p}));this.direction=this.queue.shift()||this.direction;const d=DIRS[this.direction],head={x:this.body[0].x+d.x,y:this.body[0].y+d.y},eat=head.x===this.food?.x&&head.y===this.food?.y;this.moves++;
  if(head.x<0||head.y<0||head.x>=SIZE||head.y>=SIZE){this.over=true;this.reason='wall';return {over:true};}
  if(this.body.slice(0,eat?undefined:-1).some(p=>p.x===head.x&&p.y===head.y)){this.over=true;this.reason='self';return {over:true};}
  this.body.unshift(head);if(eat){this.eaten++;if(this.body.length===SIZE*SIZE){this.food=null;this.over=true;this.reason='filled';}else{const free=[];for(let y=0;y<SIZE;y++)for(let x=0;x<SIZE;x++)if(!this.body.some(p=>p.x===x&&p.y===y))free.push({x,y});this.food=free[Math.floor(this.random()*free.length)];}}else this.body.pop();return {ate:eat,over:this.over};
 }
 snapshot(runId,elapsedMs){return {version:1,runId,score:this.score,eaten:this.eaten,length:this.body.length,moves:this.moves,elapsedMs:Math.floor(elapsedMs),reason:this.reason};}
}
export function validateSnakeResult(s){if(!s||s.version!==1||!['wall','self','filled'].includes(s.reason))throw Error('Invalid result');for(const k of ['score','eaten','length','moves','elapsedMs'])if(!Number.isSafeInteger(s[k]))throw Error('Invalid result');if(s.eaten<0||s.eaten>396||s.score!==s.eaten*POINTS||s.length!==START_LENGTH+s.eaten||s.moves<1||s.moves>1100000||s.eaten>s.moves||s.elapsedMs<85||s.elapsedMs>86400000||s.moves>s.elapsedMs/85+2||s.reason==='filled'&&s.length!==400||s.reason!=='filled'&&s.length===400)throw Error('Invalid result');return s;}
