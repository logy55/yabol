import {Output,Mp4OutputFormat,BufferTarget,CanvasSource,Quality,getFirstEncodableVideoCodec} from './video-encoder.js?v=20261024-game-replay';
const colours=['#4976b7','#d89445','#7b9a77','#aa79a9','#ca7475','#648c9d','#a79853','#818ac0','#cc925e','#6aab99','#a6816a','#a1718b'];
const WIDTH=960,SCENE_HEIGHT=600,FPS=30;
const yieldTask=()=>new Promise(resolve=>{const channel=new MessageChannel();channel.port1.onmessage=()=>{channel.port1.close();channel.port2.close();resolve();};channel.port2.postMessage(null);});
const cancelled=()=>new DOMException('Replay export cancelled','AbortError');
export async function exportGameReplay(snapshot,{ladder,marblePlayer,signal,onProgress=()=>{}}={}){
  const scale=ladder?WIDTH/ladder.boardWidth:1,HEIGHT=ladder?Math.ceil(ladder.geometry.height*scale/2)*2:SCENE_HEIGHT;
  const codec=await getFirstEncodableVideoCodec(['avc'],{width:WIDTH,height:HEIGHT});
  if(!codec)throw Error('MP4_UNSUPPORTED');if(signal?.aborted)throw cancelled();
  const target=new BufferTarget(),output=new Output({format:new Mp4OutputFormat({fastStart:'in-memory'}),target});
  const canvas=document.createElement('canvas');canvas.width=WIDTH;canvas.height=HEIGHT;const ctx=canvas.getContext('2d',{alpha:false});
  const source=new CanvasSource(canvas,{codec:'avc',latencyMode:'realtime',quality:new Quality({bitrate:2_500_000})});output.addVideoTrack(source,{frameRate:FPS});
  const onAbort=()=>{void output.cancel().catch(()=>{});};signal?.addEventListener('abort',onAbort,{once:true});
  let stopPainter=()=>{},progress=0,scene=null;
  const round=snapshot.round;
  if(snapshot.game==='marble'){
    scene=document.createElement('canvas');scene.style.cssText=`position:fixed;left:-10000px;top:0;width:${WIDTH}px;height:${SCENE_HEIGHT}px;pointer-events:none`;
    document.body.append(scene);stopPainter=marblePlayer(scene,snapshot.movie,round,()=>progress,()=>{},undefined,{manual:true});
    if(typeof stopPainter.draw!=='function'){stopPainter();scene.remove();throw Error('Replay painter unavailable');}
  }
  function drawLadder(ms){
    const geometry=ladder.geometry;
    ctx.save();ctx.scale(scale,scale);ctx.fillStyle='#f6f9fd';ctx.fillRect(0,0,ladder.boardWidth,geometry.height);
    ctx.strokeStyle='#c0cfe0';ctx.lineWidth=3;ctx.lineCap='round';
    for(let c=0;c<round.players.length;c++){ctx.beginPath();ctx.moveTo(geometry.x(c),geometry.lineTop(c));ctx.lineTo(geometry.x(c),geometry.flapTop(c));ctx.stroke();}
    round.ladder.rungs.forEach((row,r)=>row.forEach((rung,gap)=>{if(rung){ctx.beginPath();ctx.moveTo(geometry.x(gap),geometry.rungY(r,gap));ctx.lineTo(geometry.x(gap+1),geometry.rungY(r,gap));ctx.stroke();}}));
    for(const [column,item]of ladder.paths.entries()){
      const lane=ladder.lanes[column],p=Math.max(0,Math.min(1,(ms-column*4000)/2800)),width=Math.min(geometry.labelWidth,160),chipX=geometry.x(column)-width/2;
      ctx.fillStyle='#f6f9ff';ctx.strokeStyle=colours[lane.player];ctx.lineWidth=1.5;ctx.beginPath();ctx.roundRect(chipX,geometry.chipTop(column),width,40,8);ctx.fill();ctx.stroke();
      ctx.fillStyle='#344f72';ctx.font='800 12px NanumSquareRound, sans-serif';ctx.textAlign='center';ctx.fillText(`${column+1}. ${round.players[lane.player].name.slice(0,12)}`,geometry.x(column),geometry.chipTop(column)+25);
      if(p>0){ctx.save();ctx.strokeStyle=colours[lane.player];ctx.lineWidth=5.5;ctx.setLineDash([item.length]);ctx.lineDashOffset=item.length*(1-p);ctx.stroke(new Path2D(item.path.getAttribute('d')));ctx.restore();}
      if(ms>=column*4000&&p<1){const point=item.path.getPointAtLength(item.length*p);ctx.save();ctx.translate(point.x,point.y);ctx.rotate(p*Math.PI*6);ctx.fillStyle='#fff';ctx.strokeStyle=colours[lane.player];ctx.lineWidth=2.5;ctx.beginPath();ctx.arc(0,0,11,0,Math.PI*2);ctx.fill();ctx.stroke();ctx.strokeStyle='#c97671';ctx.lineWidth=1.5;ctx.beginPath();ctx.moveTo(-6,-8);ctx.quadraticCurveTo(1,0,-6,8);ctx.moveTo(6,-8);ctx.quadraticCurveTo(-1,0,6,8);ctx.stroke();ctx.restore();}
      const revealed=ms>=column*4000+2800,label=round.outcomes[round.slots[lane.end]];
      const slotX=geometry.x(lane.end)-geometry.flapWidth/2;
      ctx.fillStyle=revealed?(label==='꽝'?'#f8e2e4':'#dcf0e5'):'#edf1f8';ctx.strokeStyle='#c9d7e7';ctx.lineWidth=1;ctx.beginPath();ctx.roundRect(slotX,geometry.flapTop(lane.end),geometry.flapWidth,44,7);ctx.fill();ctx.stroke();ctx.fillStyle=revealed?(label==='꽝'?'#a45260':'#39765e'):'#645536';ctx.font='800 13px NanumSquareRound, sans-serif';ctx.fillText(revealed?label:'?',geometry.x(lane.end),geometry.flapTop(lane.end)+28);
    }
    ctx.restore();
  }
  function drawFrame(ms,frame){
    progress=Math.min(1,ms/snapshot.duration);ctx.fillStyle='#fff';ctx.fillRect(0,0,WIDTH,HEIGHT);
    if(scene){stopPainter.draw(frame/FPS*1000);ctx.drawImage(scene,0,0,WIDTH,SCENE_HEIGHT);}else drawLadder(ms);
  }
  try{
    await output.start();const frames=Math.ceil((snapshot.duration/1000+3)*FPS);
    for(let frame=0;frame<frames;frame++){
      if(signal?.aborted)throw cancelled();drawFrame(Math.min(snapshot.duration,frame/FPS*1000),frame);await source.add(frame/FPS,1/FPS);
      if(frame%10===0){onProgress(Math.round(frame/frames*100));await yieldTask();}
    }
    if(signal?.aborted)throw cancelled();await output.finalize();if(signal?.aborted)throw cancelled();onProgress(100);
    return new Blob([target.buffer],{type:'video/mp4'});
  }catch(error){await output.cancel().catch(()=>{});throw error;}
  finally{signal?.removeEventListener('abort',onAbort);stopPainter();scene?.remove();}
}
