import{findSolvableDeal}from'./search.js?v=20261107-game-consistency';
self.onmessage=event=>{try{self.postMessage({result:findSolvableDeal(event.data.seed)});}catch(error){self.postMessage({error:error.message});}};
