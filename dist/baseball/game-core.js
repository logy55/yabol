export const WIDTH=440,HEIGHT=610,FLOOR=586,DANGER=124,DROP_Y=63;
export const PHYSICS_VERSION=3;
// Regulation adult ball-size order; squash and table-tennis balls are both about 40 mm.
// Visual growth is exaggerated for playability. The final baseball is intentionally fictional.
export const BALLS=Object.freeze([
  {name:'스쿼시공',r:14,colour:'#283241',kind:'squash'},
  {name:'탁구공',r:18,colour:'#f7a542',kind:'ping'},
  {name:'골프공',r:24,colour:'#fcfcfa',kind:'golf'},
  {name:'테니스공',r:31,colour:'#c4dd5a',kind:'tennis'},
  {name:'핸드볼공',r:40,colour:'#eda748',kind:'handball'},
  {name:'배구공',r:50,colour:'#f5cf58',kind:'volleyball'},
  {name:'볼링공',r:61,colour:'#9e85c7',kind:'bowling'},
  {name:'축구공',r:74,colour:'#f8faf9',kind:'football'},
  {name:'농구공',r:87,colour:'#d88943',kind:'basketball'},
  {name:'럭비공',r:90,rx:113,ry:64,colour:'#b96d42',kind:'rugby'},
  {name:'야구공',r:132,colour:'#fff9eb',kind:'baseball'}
]);

export function createBallRandom(seed){let state=seed>>>0;const random=()=>{state=(state+0x6D2B79F5)>>>0;let t=Math.imul(state^(state>>>15),1|state);t^=t+Math.imul(t^(t>>>7),61|t);return((t^(t>>>14))>>>0)/4294967296;};random.getState=()=>state;random.setState=value=>{state=value>>>0;};return random;}
export class BallGame{
  // Older cached clients omit this option; keep their replay on the original rules.
  constructor(Matter,{physicsVersion=1,random=Math.random,onChange=()=>{},onMerge=()=>{},onOver=()=>{},onDrop=()=>{}}={}){
    if(![1,2,3].includes(physicsVersion))throw Error('Unsupported physics version');
    this.physicsVersion=physicsVersion;
    this.M=Matter;this.random=random;this.onChange=onChange;this.onMerge=onMerge;this.onOver=onOver;this.onDrop=onDrop;
    this.engine=Matter.Engine.create({enableSleeping:true,positionIterations:8,velocityIterations:8});
    this.engine.gravity.y=physicsVersion===1?1.15:1.08;this.queue=[];this.reserved=new Set();
    Matter.Events.on(this.engine,'collisionStart collisionActive',event=>this.collisions(event.pairs));
    this.reset();
  }
  pick(){const n=this.random();return n<.28?0:n<.56?1:n<.79?2:n<.96?3:4;}
  reset(){
    const {Composite,Bodies,Engine}=this.M;Composite.clear(this.engine.world,false);Engine.clear(this.engine);
    const floorFriction=this.physicsVersion===1?.5:.14,wallFriction=this.physicsVersion===1?.16:.1;
    const boundaries=[Bodies.rectangle(WIDTH/2,FLOOR+25,WIDTH+90,50,{isStatic:true,friction:floorFriction}),Bodies.rectangle(-14,HEIGHT/2,40,HEIGHT*4,{isStatic:true,friction:wallFriction}),Bodies.rectangle(WIDTH+14,HEIGHT/2,40,HEIGHT*4,{isStatic:true,friction:wallFriction})];this.boundaries=boundaries;this.nextBodyId=1;for(const body of boundaries)body.id=this.nextBodyId++;Composite.add(this.engine.world,boundaries);
    this.balls=[];this.queue=[];this.reserved.clear();this.time=0;this.frame=0;this.score=0;this.merges=0;this.drops=0;this.maxLevel=0;this.status='playing';this.overflow=0;this.nextDrop=0;this.pendingTurn=false;this.current=this.pick();this.next=this.pick();this.aim=WIDTH/2;this.onChange(this);
  }
  aimAt(x){const def=BALLS[this.current],edge=(def.rx||def.r)+10;this.aim=Math.max(edge,Math.min(WIDTH-edge,x));}
  spawn(level,x,y,{born=this.time}={}){
    const def=BALLS[level];if(!def)throw Error('Invalid ball level');
    const legacy=this.physicsVersion===1;
    const options={restitution:legacy?.14:.28,friction:legacy?.32:.12,frictionStatic:legacy?.65:.45,frictionAir:legacy?.006:.002,density:.0018,sleepThreshold:legacy?70:100,label:'game-ball'};
    // Matter's default small circles have only 14–24 sides. A consistent 32-sided
    // hull rolls smoothly without the contact changes of a visibly faceted ball.
    const body=legacy?this.M.Bodies.circle(x,y,def.r,options):this.M.Bodies.polygon(x,y,32,def.r,{...options,circleRadius:def.r});
    if(def.rx)this.M.Body.scale(body,def.rx/def.r,def.ry/def.r);
    body.id=this.nextBodyId++;body.plugin.ball={level,born,dead:false};this.maxLevel=Math.max(this.maxLevel,level);this.balls.push(body);this.M.Composite.add(this.engine.world,body);return body;
  }
  drop(x=this.aim){
    if(this.status!=='playing'||this.pendingTurn)return false;
    this.aimAt(x);const dropped=this.spawn(this.current,this.aim,DROP_Y);if(this.physicsVersion>=3)this.wakeNearby([dropped]);this.drops++;this.nextDrop=this.time+680;this.pendingTurn=true;this.onDrop({frame:this.frame,x:this.aim});this.onChange(this);return true;
  }
  collisions(pairs){
    if(this.status!=='playing')return;
    for(const pair of pairs){const a=pair.bodyA,b=pair.bodyB,aa=a.plugin.ball,bb=b.plugin.ball;
      if(this.physicsVersion>=3&&aa&&bb&&a.isSleeping!==b.isSleeping)this.M.Sleeping.set(a.isSleeping?a:b,false);
      if(!aa||!bb||aa.dead||bb.dead||aa.level!==bb.level||this.reserved.has(a.id)||this.reserved.has(b.id))continue;
      this.reserved.add(a.id);this.reserved.add(b.id);this.queue.push([a,b]);
    }
  }
  mergeQueued(){
    const pending=this.queue.splice(0);this.reserved.clear();
    for(const [a,b]of pending){const aa=a.plugin.ball,bb=b.plugin.ball;if(aa.dead||bb.dead)continue;
      aa.dead=bb.dead=true;const level=aa.level+1,x=(a.position.x+b.position.x)/2,y=(a.position.y+b.position.y)/2;
      const vx=(a.velocity.x+b.velocity.x)/2,vy=(a.velocity.y+b.velocity.y)/2;
      this.M.Composite.remove(this.engine.world,[a,b]);this.balls=this.balls.filter(ball=>ball!==a&&ball!==b);
      if(level<BALLS.length){const def=BALLS[level],rx=def.rx||def.r;const made=this.spawn(level,Math.max(rx+7,Math.min(WIDTH-rx-7,x)),Math.min(FLOOR-(def.ry||def.r),y));const legacy=this.physicsVersion===1;this.M.Body.setVelocity(made,{x:Math.max(legacy?-3:-6,Math.min(legacy?3:6,vx)),y:Math.max(legacy?-2:-4,Math.min(legacy?3:6,vy))});if(!legacy){this.M.Body.setAngle(made,(a.angle+b.angle)/2);this.M.Body.setAngularVelocity(made,Math.max(-.14,Math.min(.14,(a.angularVelocity+b.angularVelocity)*.35)));}this.maxLevel=Math.max(this.maxLevel,level);}
      const points=level<BALLS.length?(level+1)*(level+2)/2:500;
      this.score+=points;this.merges++;this.overflow=0;this.onMerge({x,y,level:Math.min(level,BALLS.length-1),points,cleared:level>=BALLS.length});this.onChange(this);
    }
    if(pending.length&&this.physicsVersion>=3)this.wakeNearby(pending.flat());
  }
  wakeNearby(changed){for(const body of this.balls)if(body.isSleeping)for(const neighbour of changed){const a=body.bounds,b=neighbour.bounds;if(a.max.x+2>=b.min.x&&a.min.x-2<=b.max.x&&a.max.y+2>=b.min.y&&a.min.y-2<=b.max.y){this.M.Sleeping.set(body,false);break;}}}
  wakeUnsupported(){
    if(!this.balls.some(body=>body.isSleeping))return;
    // Sleeping bodies do not wake from gravity when their support disappears.
    // Follow current geometric contacts from the static floor/walls, rather than
    // cached collision pairs that may still refer to removed merge parents.
    const supported=new Set(),frontier=[...this.boundaries];
    for(let at=0;at<frontier.length;at++)for(const body of this.balls){
      if(supported.has(body))continue;const anchor=frontier[at],a=body.bounds,b=anchor.bounds;
      if(a.max.x<b.min.x||a.min.x>b.max.x||a.max.y<b.min.y||a.min.y>b.max.y)continue;
      if(this.M.Collision.collides(body,anchor)){supported.add(body);frontier.push(body);}
    }
    for(const body of this.balls)if(body.isSleeping&&!supported.has(body))this.M.Sleeping.set(body,false);
  }
  step(dt=1000/60){
    if(this.status!=='playing')return;this.frame++;this.time+=dt;if(this.physicsVersion>=3&&this.frame%30===0)this.wakeUnsupported();this.M.Engine.update(this.engine,dt);this.mergeQueued();
    if(this.pendingTurn&&this.time>=this.nextDrop){this.current=this.next;this.next=this.pick();this.pendingTurn=false;this.aimAt(this.aim);this.onChange(this);}
    let danger=false;
    for(const body of this.balls){
      const maxSpeed=this.physicsVersion===1?15:22;
      if(body.speed>maxSpeed)this.M.Body.setVelocity(body,{x:body.velocity.x/body.speed*maxSpeed,y:body.velocity.y/body.speed*maxSpeed});
      // A newly dropped ball crosses the line. It must not immediately lose the game.
      if(this.time-body.plugin.ball.born>1800&&body.bounds.min.y<DANGER&&(body.isSleeping||body.speed<1.7))danger=true;
    }
    this.overflow=danger?this.overflow+dt:0;
    if(this.overflow>=2300){this.status='over';this.onChange(this);this.onOver(this);}
  }
  pause(){if(this.status!=='playing')return false;this.status='paused';this.onChange(this);return true;}
  resume(){if(this.status!=='paused')return false;this.status='playing';this.onChange(this);return true;}
  dispose(){this.M.Events.off(this.engine);this.M.Composite.clear(this.engine.world,false);this.M.Engine.clear(this.engine);}
}
