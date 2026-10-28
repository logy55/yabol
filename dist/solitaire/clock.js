export class GameClock{
 constructor(now=()=>performance.now()){this.now=now;this.total=0;this.anchor=null;}
 get elapsed(){return this.total+(this.anchor===null?0:Math.max(0,this.now()-this.anchor));}
 resume(){if(this.anchor===null)this.anchor=this.now();}
 pause(){this.total=this.elapsed;this.anchor=null;}
 reset(){this.total=0;this.anchor=null;}
}
