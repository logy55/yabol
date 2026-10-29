import{solitaireScore}from'./result.js?v=20261029-solitaire-play';
import{helpfulHint,nextFoundation,positionKey}from'./strategy.js?v=20261029-solitaire-play';
export const SUITS=['♠','♦','♥','♣'],SUIT_NAMES=['스페이드','다이아','하트','클로버'];
export const rank=id=>id%13+1,suit=id=>Math.floor(id/13),red=id=>suit(id)===1||suit(id)===2;
export function seededRandom(seed){let n=seed>>>0;return()=>{n+=0x6D2B79F5;let v=n;v=Math.imul(v^v>>>15,v|1);v^=v+Math.imul(v^v>>>7,v|61);return((v^v>>>14)>>>0)/4294967296;};}
export class Klondike{
 constructor(seed){const random=seededRandom(seed),deck=Array.from({length:52},(_,id)=>id);for(let i=51;i>0;i--){const j=Math.floor(random()*(i+1));[deck[i],deck[j]]=[deck[j],deck[i]];}this.tableau=Array.from({length:7},()=>[]);for(let row=0;row<7;row++)for(let col=row;col<7;col++)this.tableau[col].push({id:deck.pop(),up:col===row});this.stock=deck;this.waste=[];this.foundations=Array.from({length:4},()=>[]);this.stats={foundation:0,waste:0,flips:0,returns:0,recycles:0,undos:0,hints:0};this.moves=0;this.history=[];this.hintCharges=new Set();}
 get won(){return this.foundations.every(p=>p.length===13);}
 get score(){return solitaireScore(this.stats,this.won);}
 state(){return{tableau:this.tableau.map(p=>p.map(c=>({...c}))),stock:[...this.stock],waste:[...this.waste],foundations:this.foundations.map(p=>[...p]),stats:{...this.stats}};}
 remember(){this.history.push(this.state());if(this.history.length>150)this.history.shift();}
 draw(){if(this.won||!this.stock.length&&!this.waste.length)return false;this.remember();if(this.stock.length){for(let i=0;i<3&&this.stock.length;i++)this.waste.push(this.stock.pop());}else{this.stock=this.waste.reverse();this.waste=[];this.stats.recycles++;}this.moves++;return true;}
 cards(source){if(!source)return[];if(source.kind==='waste')return this.waste.length?[this.waste.at(-1)]:[];if(source.kind==='foundation'){const p=this.foundations[source.pile];return p?.length?[p.at(-1)]:[];}if(source.kind!=='tableau'||!Number.isInteger(source.pile)||!Number.isInteger(source.index))return[];const p=this.tableau[source.pile];if(!p||source.index<0||source.index>=p.length)return[];const run=p.slice(source.index);if(!run.every(c=>c.up)||run.some((c,i)=>i&&!(rank(run[i-1].id)===rank(c.id)+1&&red(run[i-1].id)!==red(c.id))))return[];return run.map(c=>c.id);}
 canMove(source,target){const cards=this.cards(source);if(!cards.length||!target||this.won)return false;const first=cards[0];if(target.kind==='foundation'){const p=this.foundations[target.pile];return cards.length===1&&source.kind!=='foundation'&&!!p&&suit(first)===target.pile&&rank(first)===p.length+1;}if(target.kind!=='tableau'||source.kind==='tableau'&&source.pile===target.pile)return false;const p=this.tableau[target.pile];return !!p&&(!p.length?rank(first)===13:p.at(-1).up&&red(p.at(-1).id)!==red(first)&&rank(p.at(-1).id)===rank(first)+1);}
 move(source,target){if(!this.canMove(source,target))return false;this.remember();const cards=this.cards(source);if(source.kind==='tableau'){const p=this.tableau[source.pile];p.splice(source.index);if(p.length&&!p.at(-1).up){p.at(-1).up=true;this.stats.flips++;}}else if(source.kind==='waste'){this.waste.pop();if(target.kind==='tableau')this.stats.waste++;}else{this.foundations[source.pile].pop();this.stats.returns++;}if(target.kind==='foundation'){this.foundations[target.pile].push(...cards);this.stats.foundation++;}else this.tableau[target.pile].push(...cards.map(id=>({id,up:true})));this.moves++;return true;}
 undo(){if(!this.history.length||this.won)return false;const undos=this.stats.undos+1,hints=this.stats.hints||0,previous=this.history.pop();Object.assign(this,previous);this.stats.undos=undos;this.stats.hints=hints;this.moves++;return true;}
 sources(){return[...(this.waste.length?[{kind:'waste'}]:[]),...this.tableau.flatMap((p,pile)=>p.flatMap((c,index)=>c.up?[{kind:'tableau',pile,index}]:[]))];}
 hint(){return helpfulHint(this);}
 nextFoundation(){return nextFoundation(this);}
 takeHint(){const hint=this.hint();let charged=false;if(hint?.source){const key=positionKey(this)+'|'+JSON.stringify(hint);if(!this.hintCharges.has(key)){this.hintCharges.add(key);this.stats.hints=(this.stats.hints||0)+1;charged=true;}}return{hint,charged};}
 get canAutoComplete(){return !this.won&&!this.stock.length&&!this.waste.length&&this.tableau.every(p=>p.every(c=>c.up));}
 snapshot(runId,elapsedMs){return{runId,foundations:this.foundations.map(p=>[...p]),stats:{...this.stats},score:this.score,moves:this.moves,elapsedMs:Math.floor(elapsedMs)};}
}
