// Original, cached sports-ball artwork. Clear, restrained seams at game size.
const TAU=Math.PI*2;
const unit=v=>{const n=Math.hypot(...v)||1;return v.map(x=>x/n);};
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const mix=(a,b,t)=>unit(a.map((v,i)=>v+(b[i]-v)*t));
function rotate(p,x=0,y=0,z=0){let[a,b,c]=p;[b,c]=[b*Math.cos(x)-c*Math.sin(x),b*Math.sin(x)+c*Math.cos(x)];[a,c]=[a*Math.cos(y)+c*Math.sin(y),-a*Math.sin(y)+c*Math.cos(y)];return[a*Math.cos(z)-b*Math.sin(z),a*Math.sin(z)+b*Math.cos(z),c];}
const palette={squash:'#30343a',ping:'#f69b36',golf:'#f1f3ee',tennis:'#c1d83f',handball:'#eda748',volleyball:'#f3ca32',bowling:'#674b9f',football:'#f3f2e9',basketball:'#cf792e',rugby:'#a3653f',baseball:'#fffdf5'};
function path(c,points,close=false){c.beginPath();points.forEach((p,i)=>c[i?'lineTo':'moveTo'](p[0]*100,p[1]*100));if(close)c.closePath();}
function visibleCurve(c,points,colour,width){
  c.strokeStyle=colour;c.lineWidth=width;c.lineCap='round';let active=false;
  c.beginPath();for(const p of points){if(p[2]<.005){if(active)c.stroke();c.beginPath();active=false;continue;}if(active)c.lineTo(p[0]*100,p[1]*100);else{c.moveTo(p[0]*100,p[1]*100);active=true;}}if(active)c.stroke();
}
function cubic(points,t){const s=1-t;return[0,1].map(k=>s*s*s*points[0][k]+3*s*s*t*points[1][k]+3*s*t*t*points[2][k]+t*t*t*points[3][k]);}
function seam(c,points,colour,width){c.beginPath();c.moveTo(...points[0]);c.bezierCurveTo(...points.slice(1).flat());c.strokeStyle=colour;c.lineWidth=width;c.lineCap='round';c.stroke();}
function baseball(c){
  c.save();c.rotate(-.20);
  for(const sign of [-1,1]){
    const points=[[sign*65,-80],[sign*43,-40],[sign*43,40],[sign*65,80]];
    seam(c,points,'#bbaea16b',2.3);seam(c,points,'#ceaca38a',.75);
    // Evenly spaced pairs of red thread meet on the leather join.
    const samples=Array.from({length:241},(_,i)=>cubic(points,i/240)),lengths=[0];
    for(let i=1;i<samples.length;i++)lengths.push(lengths[i-1]+Math.hypot(samples[i][0]-samples[i-1][0],samples[i][1]-samples[i-1][1]));
    let at=1;for(let i=0;i<16;i++){
      const distance=(i+.5)*lengths.at(-1)/16;while(at<240&&lengths[at]<distance)at++;
      const p=samples[at],a=samples[Math.max(0,at-1)],b=samples[Math.min(240,at+1)],n=Math.hypot(b[0]-a[0],b[1]-a[1]),tx=(b[0]-a[0])/n,ty=(b[1]-a[1])/n;
      c.beginPath();c.moveTo(p[0]-ty*4.3+tx*2,p[1]+tx*4.3+ty*2);c.lineTo(p[0]-tx*1.7,p[1]-ty*1.7);c.lineTo(p[0]+ty*4.3+tx*2,p[1]-tx*4.3+ty*2);
      c.strokeStyle='#c2343d';c.lineWidth=1.9;c.lineCap='round';c.lineJoin='round';c.stroke();
    }
  }
  c.restore();
}
function tennis(c){
  c.save();c.rotate(.43);
  for(const sign of [-1,1]){
    const points=[[sign*64,-80],[sign*40,-44],[sign*40,44],[sign*64,80]];
    seam(c,points,'#67852155',10);seam(c,points,'#fafbe6',7.5);seam(c,points,'#ffffff80',2);
  }
  c.restore();
}
function grain(c,kind){
  const count=kind==='tennis'?1500:kind==='basketball'?1200:kind==='baseball'?850:450;
  for(let i=0;i<count;i++){const a=i*2.3999632297,z=(i+.5)/count,r=Math.sqrt(1-z*z)*98,x=Math.cos(a)*r,y=Math.sin(a)*r;
    c.fillStyle=i%3?'#09131d0b':'#ffffff30';c.beginPath();c.ellipse(x,y,kind==='basketball'?.85:.38,kind==='tennis'?.65:.35,a,0,TAU);c.fill();}
}
function golf(c){
  for(let i=0;i<680;i++){
    const z=1-2*(i+.5)/680;if(z<.04)continue;const a=i*2.3999632297,r=Math.sqrt(1-z*z)*99,x=r*Math.cos(a),y=r*Math.sin(a),size=3.45*(.35+.65*z);
    const d=c.createRadialGradient(x-size*.25,y-size*.3,.2,x,y,size);d.addColorStop(0,'#8f9ca96e');d.addColorStop(.8,'#c2ccd16b');d.addColorStop(1,'#ffffffa1');c.fillStyle=d;c.beginPath();c.ellipse(x,y,size,size*(.35+.65*z),a,0,TAU);c.fill();
  }
}
function soccerMesh(){
  const g=(1+Math.sqrt(5))/2,vertices=[];for(const a of [-1,1])for(const b of [-g,g])vertices.push(unit([0,a,b]),unit([a,b,0]),unit([b,0,a]));
  const distance=(a,b)=>Math.hypot(...a.map((n,i)=>n-b[i]));let edge=Infinity;for(let i=0;i<12;i++)for(let j=i+1;j<12;j++)edge=Math.min(edge,distance(vertices[i],vertices[j]));
  const neighbours=vertices.map(v=>vertices.map((p,i)=>Math.abs(distance(v,p)-edge)<1e-5?i:-1).filter(i=>i>=0));
  const cut=(i,j)=>unit(vertices[i].map((v,k)=>(2*v+vertices[j][k])/3)),faces=[];
  for(let i=0;i<12;i++){
    const normal=vertices[i],u=unit(cross(normal,Math.abs(normal[1])<.9?[0,1,0]:[1,0,0])),v=cross(normal,u),dot=(a,b)=>a.reduce((s,n,k)=>s+n*b[k],0);
    const ring=neighbours[i].map(j=>cut(i,j)).sort((a,b)=>Math.atan2(dot(a,v),dot(a,u))-Math.atan2(dot(b,v),dot(b,u)));faces.push({points:ring,black:true,index:faces.length});
  }
  for(let i=0;i<12;i++)for(const j of neighbours[i])for(const k of neighbours[j])if(i<j&&j<k&&neighbours[k].includes(i))faces.push({points:[cut(i,j),cut(j,i),cut(j,k),cut(k,j),cut(k,i),cut(i,k)],black:false,index:faces.length});
  return faces;
}
const mesh=soccerMesh();
function paintFaces(c,faces,rotation,colour){
  const projected=faces.map(face=>{const points=[];for(let i=0;i<face.points.length;i++)for(let s=0;s<12;s++)points.push(rotate(mix(face.points[i],face.points[(i+1)%face.points.length],s/12),...rotation));return{...face,points,depth:points.reduce((v,p)=>v+p[2],0)/points.length};}).filter(f=>f.points.some(p=>p[2]>0)).sort((a,b)=>a.depth-b.depth);
  for(const face of projected){const points=face.points.map(p=>p[2]<0?unit([p[0],p[1],0]):p);path(c,points,true);c.fillStyle=colour(face);c.fill();c.strokeStyle='#21394c62';c.lineWidth=.95;c.lineJoin='round';c.stroke();}
}
function panels(c){paintFaces(c,mesh,[.16,-.10,.16],f=>f.black?'#273440':'#f7f5ed');}
function handball(c){
  // Three curved grip panels, rather than a football's pentagon/hexagon skin.
  for(let i=0;i<3;i++){
    c.save();c.rotate(i*TAU/3+.16);c.beginPath();c.moveTo(-22,-103);
    c.bezierCurveTo(30,-96,55,-68,56,-27);c.bezierCurveTo(57,2,40,28,12,44);
    c.lineTo(-16,19);c.bezierCurveTo(15,-6,24,-46,-22,-103);c.closePath();
    c.fillStyle='#27577a';c.fill();c.strokeStyle='#f8dfaa';c.lineWidth=2;c.lineJoin='round';c.stroke();
    seam(c,[[-22,-103],[-52,-68],[-82,-41],[-100,-8]],'#8a632b8c',1.1);c.restore();
  }
  for(let i=0;i<950;i++){const a=i*2.399963,z=(i+.5)/950,r=Math.sqrt(1-z*z)*98,x=Math.cos(a)*r,y=Math.sin(a)*r;c.fillStyle=i%2?'#13293c20':'#fff8d942';c.beginPath();c.arc(x,y,.8,0,TAU);c.fill();}
}
function volleyball(c){
  const sphere=(theta,phi)=>[Math.cos(phi)*Math.cos(theta),Math.sin(phi),Math.cos(phi)*Math.sin(theta)],faces=[];
  for(let col=0;col<6;col++)for(let row=0;row<3;row++){const a=col*TAU/6,b=(col+1)*TAU/6,lo=-Math.PI/2+row*Math.PI/3,hi=lo+Math.PI/3;faces.push({points:[sphere(a,lo),sphere(b,lo),sphere(b,hi),sphere(a,hi)],index:col*3+row});}
  paintFaces(c,faces,[.32,.55,-.25],f=>['#e8b824','#2457a1','#ffde51'][Math.floor(f.index/3)%3]);
}
function bowling(c){
  c.save();c.lineCap='round';for(let i=0;i<9;i++){c.strokeStyle=i%2?'#b6a6db38':'#302b5830';c.lineWidth=i%2?9:5;c.beginPath();c.moveTo(-130,-90+i*22);c.bezierCurveTo(-30,50+i*13,35,-80+i*10,125,10+i*20);c.stroke();}c.restore();
  for(const [x,y,r]of [[-22,-25,11],[12,-29,11],[4,17,15]]){const g=c.createRadialGradient(x-2,y-3,1,x,y,r);g.addColorStop(0,'#151c30');g.addColorStop(.76,'#1f213e');g.addColorStop(1,'#c9bce292');c.fillStyle=g;c.beginPath();c.ellipse(x,y,r,r*.92,-.17,0,TAU);c.fill();c.strokeStyle='#291e4d8c';c.lineWidth=1.4;c.stroke();}
}
function basketball(c){
  const curves=[];
  for(const axis of [0,1])curves.push(Array.from({length:241},(_,i)=>{const a=-Math.PI/2+i/240*Math.PI;return rotate(axis?[Math.sin(a),0,Math.cos(a)]:[0,Math.sin(a),Math.cos(a)],0,0,.17);}));
  for(const sign of [-1,1])curves.push(Array.from({length:241},(_,i)=>{const y=-.8+i/240*1.6,x=sign*(.28+.5*y*y);return rotate([x,y,Math.sqrt(Math.max(0,1-x*x-y*y))],0,0,.17);}));
  for(const points of curves){visibleCurve(c,points,'#edb36d',4.5);visibleCurve(c,points,'#603a23',2.6);}
}
function rugby(c){
  // Classic leather rugby ball: four leather panels and a short laced join.
  for(const sign of [-1,1]){
    c.save();c.scale(1,sign);
    c.beginPath();c.moveTo(-99,0);c.bezierCurveTo(-45,-61,45,-61,99,0);c.bezierCurveTo(45,-86,-45,-86,-99,0);c.closePath();c.fillStyle='#76452d38';c.fill();
    seam(c,[[-99,0],[-43,-65],[43,-65],[99,0]],'#633b29',1.9);
    seam(c,[[-99,2],[-43,-62],[43,-62],[99,2]],'#d9a27175',.9);
    c.restore();
  }
  seam(c,[[-98,0],[-38,3],[38,3],[98,0]],'#603b2a',1.5);
  c.strokeStyle='#ead5ac';c.lineWidth=2.7;c.lineCap='round';
  for(let x=-29;x<=29;x+=8.3){c.beginPath();c.moveTo(x-1,-8);c.lineTo(x+1,11);c.stroke();}
  seam(c,[[-35,-7],[-12,-9],[12,-9],[35,-7]],'#dcc39a',1.5);seam(c,[[-35,10],[-12,12],[12,12],[35,10]],'#dcc39a',1.5);
}

export function createBallArt(definitions){
  const sprites=definitions.map(def=>{
    const r=def.r,rx=def.rx||r,ry=def.ry||r,pad=9,density=Math.max(2,96/Math.min(rx,ry));
    const image=document.createElement('canvas');image.width=Math.ceil((rx+pad)*2*density);image.height=Math.ceil((ry+pad)*2*density);
    const c=image.getContext('2d');c.scale(density,density);c.translate(rx+pad,ry+pad);c.scale(rx/100,ry/100);
    c.shadowColor='#14283c40';c.shadowBlur=3;c.shadowOffsetY=1.5;c.beginPath();c.arc(0,0,99.5,0,TAU);c.fillStyle=palette[def.kind];c.fill();c.shadowColor='transparent';
    c.save();c.beginPath();c.arc(0,0,99.5,0,TAU);c.clip();
    if(def.kind==='golf')golf(c);
    else if(def.kind==='tennis'){grain(c,def.kind);tennis(c);}
    else if(def.kind==='baseball'){grain(c,def.kind);baseball(c);}
    else if(def.kind==='handball')handball(c);
    else if(def.kind==='football'){panels(c);grain(c,def.kind);}
    else if(def.kind==='volleyball'){volleyball(c);grain(c,def.kind);}
    else if(def.kind==='bowling')bowling(c);
    else if(def.kind==='basketball'){grain(c,def.kind);basketball(c);}
    else if(def.kind==='rugby'){rugby(c);grain(c,def.kind);}
    else if(def.kind==='squash'){grain(c,def.kind);for(const x of [-12,12]){c.fillStyle='#e4c546';c.beginPath();c.arc(x,14,7,0,TAU);c.fill();}}
    // Ping-pong has no lettering or logo.
    const shade=c.createRadialGradient(-31,-38,7,-16,-18,130);shade.addColorStop(0,'#ffffff40');shade.addColorStop(.45,'#ffffff00');shade.addColorStop(.76,'#17222d09');shade.addColorStop(1,def.kind==='squash'?'#080c165c':'#15212e4d');c.fillStyle=shade;c.fillRect(-100,-100,200,200);
    const sheen=c.createRadialGradient(-38,-47,0,-30,-40,63);sheen.addColorStop(0,def.kind==='bowling'?'#ffffffab':'#ffffff4a');sheen.addColorStop(.37,'#ffffff15');sheen.addColorStop(1,'#ffffff00');c.fillStyle=sheen;c.fillRect(-100,-100,200,200);c.restore();
    c.strokeStyle=def.kind==='squash'?'#0d1c2e72':'#18304448';c.lineWidth=.9;c.beginPath();c.arc(0,0,99.1,0,TAU);c.stroke();
    return{image,rx,ry,pad};
  });
  function draw(context,level,x,y,scale=1,angle=0,alpha=1){const s=sprites[level];context.save();context.translate(x,y);context.rotate(angle);context.globalAlpha=alpha;context.drawImage(s.image,-(s.rx+s.pad)*scale,-(s.ry+s.pad)*scale,(s.rx+s.pad)*2*scale,(s.ry+s.pad)*2*scale);context.restore();}
  function icon(canvas,level,size){const c=canvas.getContext('2d'),def=definitions[level];c.clearRect(0,0,canvas.width,canvas.height);draw(c,level,canvas.width/2,canvas.height/2,size/Math.max(def.rx||def.r,def.ry||def.r));}
  return{draw,icon,sprites};
}
