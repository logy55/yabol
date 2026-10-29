import{findSolvableDeal}from'./search.js?v=20261029-solitaire-play';
self.onmessage=event=>{try{self.postMessage({result:findSolvableDeal(event.data.seed)});}catch(error){self.postMessage({error:error.message});}};
