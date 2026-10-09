export const yabolticons = Object.freeze([
  {id:'hello',label:'안녕'}, {id:'laugh',label:'ㅋㅋㅋ'},
  {id:'cheer',label:'응원'}, {id:'homerun',label:'홈런!'},
  {id:'cry',label:'눈물'}, {id:'angry',label:'분노'},
  {id:'clap',label:'박수'}, {id:'thanks',label:'고마워'}
]);
export const getYabolticon = id => yabolticons.find(item=>item.id===id);
export const yabolticonHTML = id => {
  const item=getYabolticon(id);
  return item?`<span class="yabolticon yabol-${item.id}" role="img" aria-label="야볼티콘 ${item.label}" title="${item.label}"></span>`:'';
};

export function renderYabolText(value){
  const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  return String(value??'').split(/(\[야볼티콘:[a-z]+\])/g).map(part=>{
    const id=part.match(/^\[야볼티콘:([a-z]+)\]$/)?.[1];
    return id&&getYabolticon(id)?yabolticonHTML(id):escape(part);
  }).join('');
}
