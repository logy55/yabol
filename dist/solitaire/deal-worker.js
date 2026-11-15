import{findSolvableDeal}from'./search.js?v=20261115-free-recycle';
self.onmessage=event=>{try{self.postMessage({result:findSolvableDeal(event.data.seed)});}catch(error){self.postMessage({error:error.message});}};
