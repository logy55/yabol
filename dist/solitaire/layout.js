// Fit every legal column (up to six hidden cards plus a thirteen-card run)
// inside a fixed board. Long columns use a readable inline rank/suit band.
export function solitaireLayout(width,height,piles,{compact=false}={}){
 width=Math.max(1,width);height=Math.max(1,height);
 const gap=compact?5:8,topGap=compact?10:18,ratio=1.43;
 const maximum=Math.max(10,Math.min(114,(width-gap*6)/7));
 const counts=piles.map(p=>({hidden:p.slice(0,-1).filter(c=>!c.up).length,up:p.slice(0,-1).filter(c=>c.up).length}));
 const minimum=w=>({hidden:2,up:Math.max(9,Math.min(18,w*.22))});
 const fits=w=>{const step=minimum(w);return counts.every(c=>2*w*ratio+topGap+c.hidden*step.hidden+c.up*step.up<=height-.5);};
 let cardWidth=maximum;while(cardWidth>10&&!fits(cardWidth))cardWidth-=.5;
 cardWidth=Math.max(10,cardWidth);const cardHeight=cardWidth*ratio,tableauHeight=Math.max(cardHeight,height-cardHeight-topGap),min=minimum(cardWidth);
 const columns=piles.map((pile,i)=>{
  const c=counts[i],room=Math.max(0,tableauHeight-cardHeight),preferred={hidden:Math.max(2,Math.min(11,cardWidth*.14)),up:Math.max(min.up,Math.min(32,cardWidth*.33))};
  const base=c.hidden*min.hidden+c.up*min.up,extra=c.hidden*(preferred.hidden-min.hidden)+c.up*(preferred.up-min.up),scale=extra?Math.max(0,Math.min(1,(room-base)/extra)):1;
  const hidden=min.hidden+(preferred.hidden-min.hidden)*scale,up=min.up+(preferred.up-min.up)*scale;let y=0;
  const offsets=pile.map((card,index)=>{const offset=y;if(index<pile.length-1)y+=card.up?up:hidden;return offset;});
  return{offsets,hiddenStep:hidden,faceStep:up,bottom:(offsets.at(-1)||0)+cardHeight};
 });
 return{cardWidth,cardHeight,gap,topGap,rowWidth:7*cardWidth+6*gap,tableauHeight,columns};
}
