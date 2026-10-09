import {getYabolticon,yabolticonHTML} from './yabolticons.js';

const blockTypes=['paragraph','heading','blockquote','bulletList','orderedList','codeBlock','horizontalRule','table','image'];
const children={doc:blockTypes,paragraph:['text','hardBreak','yabolticon'],heading:['text','hardBreak','yabolticon'],codeBlock:['text'],blockquote:blockTypes,bulletList:['listItem'],orderedList:['listItem'],listItem:blockTypes,table:['tableRow'],tableRow:['tableCell','tableHeader'],tableCell:blockTypes.filter(type=>type!=='table'),tableHeader:blockTypes.filter(type=>type!=='table')};
const marks=new Set(['bold','italic','underline','strike','code']);
const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));

// Store a small allowlisted document, not user-provided HTML or media URLs.
export function normalizeDocument(input,imageCount=5){
  let nodes=0,textLength=0;
  function visit(node,depth=0){
    if(!node||typeof node!=='object'||Array.isArray(node)||++nodes>2000||depth>10)throw new Error('본문이 너무 복잡합니다.');
    const type=node.type,result={type};
    if(type==='text'){
      if(typeof node.text!=='string')throw new Error('잘못된 본문입니다.');
      textLength+=node.text.length;if(textLength>10000)throw new Error('본문은 10,000자까지 입력할 수 있어요.');
      result.text=node.text;
      if(node.marks?.length){
        if(!Array.isArray(node.marks)||node.marks.length>5||node.marks.some(mark=>!marks.has(mark.type)))throw new Error('지원하지 않는 글자 서식입니다.');
        result.marks=node.marks.map(mark=>({type:mark.type}));
      }
      return result;
    }
    if(type==='image'){
      const index=node.attrs?.index;
      if(!Number.isInteger(index)||index<0||index>=imageCount)throw new Error('사진을 다시 삽입해 주세요.');
      return {type,attrs:{index,alt:String(node.attrs?.alt||'본문 사진').slice(0,200)}};
    }
    if(type==='yabolticon'){
      if(!getYabolticon(node.attrs?.id))throw new Error('지원하지 않는 야볼티콘입니다.');
      return {type,attrs:{id:node.attrs.id}};
    }
    if(type==='hardBreak'||type==='horizontalRule')return result;
    if(!Object.hasOwn(children,type))throw new Error('지원하지 않는 본문 형식입니다.');
    if(type==='heading')result.attrs={level:[2,3].includes(node.attrs?.level)?node.attrs.level:2};
    if(type==='orderedList')result.attrs={start:Number.isInteger(node.attrs?.start)&&node.attrs.start>0&&node.attrs.start<1000?node.attrs.start:1};
    if(type==='tableCell'||type==='tableHeader')result.attrs={colspan:bounded(node.attrs?.colspan,10),rowspan:bounded(node.attrs?.rowspan,20)};
    if(node.content!==undefined&&!Array.isArray(node.content))throw new Error('잘못된 본문입니다.');
    result.content=(node.content||[]).map(child=>{
      if(!children[type].includes(child?.type))throw new Error('지원하지 않는 본문 구조입니다.');
      return visit(child,depth+1);
    });
    if(type==='table'&&(result.content.length<1||result.content.length>20))throw new Error('표는 20행까지 사용할 수 있어요.');
    if(type==='tableRow'&&(result.content.length<1||result.content.length>10))throw new Error('표는 10열까지 사용할 수 있어요.');
    return result;
  }
  if(input?.type!=='doc')throw new Error('잘못된 본문입니다.');
  const result=visit(input);
  if(JSON.stringify(result).length>150000)throw new Error('본문이 너무 큽니다.');
  return result;
}
function bounded(value,max){return Number.isInteger(value)&&value>0&&value<=max?value:1;}
export function imageIndexes(doc){
  const found=new Set();
  function walk(node){if(node.type==='image')found.add(node.attrs.index);node.content?.forEach(walk);}
  walk(doc);return [...found];
}
export function documentText(doc){
  const visit=node=>node.type==='text'?node.text:node.type==='yabolticon'?`[${getYabolticon(node.attrs.id)?.label||'야볼티콘'}]`:node.type==='image'?'[사진]':node.type==='hardBreak'?'\n':(node.content||[]).map(visit).join(['doc','table','tableRow','bulletList','orderedList'].includes(node.type)?'\n':'');
  const text=visit(doc).trim();return text||(doc.content?.some(node=>node.type==='table')?'[표]':'');
}
export function plainDocument(text='',images=[]){
  const content=String(text).split('\n').map(line=>({type:'paragraph',content:line?[{type:'text',text:line}]:[]}));
  images.forEach((_,index)=>content.push({type:'image',attrs:{index,alt:'본문 사진'}}));
  return {type:'doc',content};
}
export function remapDocumentPhotos(doc,indexes){
  const result=structuredClone(doc);
  function walk(node){if(node.type==='image')node.attrs.index=indexes.indexOf(node.attrs.index);node.content?.forEach(walk);}
  walk(result);return normalizeDocument(result,indexes.length);
}
export function renderDocument(input,images=[],options={}){
  const doc=normalizeDocument(input,images.length);
  const resolve=options.resolveImage||((url)=>{try{const parsed=new URL(url);return parsed.protocol==='https:'&&parsed.hostname==='res.cloudinary.com'?parsed.href:'';}catch{return '';}});
  function render(node){
    if(node.type==='text'){
      let text=escapeHtml(node.text);
      for(const mark of node.marks||[]){const tag={bold:'strong',italic:'em',underline:'u',strike:'s',code:'code'}[mark.type];text=`<${tag}>${text}</${tag}>`;}
      return text;
    }
    if(node.type==='yabolticon')return yabolticonHTML(node.attrs.id);
    if(node.type==='image'){
      if(options.restricted)return `<div class="inline-photo-placeholder" data-private-photo="${node.attrs.index}">사진을 불러오는 중입니다.</div>`;
      const src=resolve(images[node.attrs.index]);
      return src?`<figure class="inline-photo"><img src="${escapeHtml(src)}" alt="${escapeHtml(node.attrs.alt)}" loading="lazy"></figure>`:'';
    }
    if(node.type==='hardBreak')return '<br>';
    if(node.type==='horizontalRule')return '<hr>';
    const inner=(node.content||[]).map(render).join('');
    if(node.type==='doc')return inner;
    if(node.type==='table')return `<div class="rich-table-scroll"><table><tbody>${inner}</tbody></table></div>`;
    if(node.type==='tableRow')return `<tr>${inner}</tr>`;
    if(node.type==='tableCell'||node.type==='tableHeader'){const tag=node.type==='tableCell'?'td':'th';return `<${tag} colspan="${node.attrs.colspan}" rowspan="${node.attrs.rowspan}">${inner}</${tag}>`;}
    if(node.type==='heading')return `<h${node.attrs.level}>${inner}</h${node.attrs.level}>`;
    if(node.type==='orderedList')return `<ol start="${node.attrs.start}">${inner}</ol>`;
    if(node.type==='codeBlock')return `<pre><code>${inner}</code></pre>`;
    const tag={paragraph:'p',blockquote:'blockquote',bulletList:'ul',listItem:'li'}[node.type];
    return `<${tag}>${inner||'<br>'}</${tag}>`;
  }
  return render(doc);
}
