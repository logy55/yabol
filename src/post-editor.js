import {Editor,Node,mergeAttributes} from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import {TableKit} from '@tiptap/extension-table';
import Image from '@tiptap/extension-image';
import {normalizeDocument,imageIndexes,documentText,plainDocument} from '../dist/rich-body.js';
import {yabolticons,getYabolticon} from '../dist/yabolticons.js';

const LocalImage=Image.extend({
  addAttributes(){return {...this.parent?.(),assetIndex:{default:null,renderHTML:attrs=>({'data-asset-index':attrs.assetIndex})}};},
  // Photos enter through the local file picker, paste or drop handler, never arbitrary pasted URLs.
  parseHTML(){return [];}
});
const Yabolticon=Node.create({
  name:'yabolticon',group:'inline',inline:true,atom:true,
  addAttributes(){return {id:{default:'hello',parseHTML:element=>element.getAttribute('data-yabol-id')}};},
  parseHTML(){return [{tag:'span[data-yabol-id]',getAttrs:element=>getYabolticon(element.getAttribute('data-yabol-id'))?{}:false}];},
  renderHTML({node}){
    const item=getYabolticon(node.attrs.id)||yabolticons[0];
    return ['span',mergeAttributes({'data-yabol-id':item.id,class:`yabolticon yabol-${item.id}`,role:'img','aria-label':`야볼티콘 ${item.label}`,title:item.label,contenteditable:'false'})];
  }
});

export function createPostEditor({root,onFiles,onUpdate,onError,onPreview}){
  const toolbar=root.querySelector('.editor-toolbar');
  const stickerPicker=root.querySelector('.yabol-picker');
  const tablePicker=root.querySelector('.table-picker');
  let savedSelection=null;
  let editor;
  editor=new Editor({
    element:root.querySelector('#post-editor'),
    extensions:[StarterKit.configure({link:false,heading:{levels:[2,3]}}),LocalImage.configure({allowBase64:false}),TableKit.configure({table:{resizable:true}}),Yabolticon],
    content:{type:'doc',content:[{type:'paragraph'}]},
    editorProps:{
      attributes:{role:'textbox','aria-label':'내용','aria-multiline':'true','data-placeholder':'이야기를 적고 사진·표·야볼티콘을 넣어 보세요.'},
      handlePaste(view,event){
        const files=Array.from(event.clipboardData?.files||[]).filter(file=>file.type.startsWith('image/'));
        if(files.length){event.preventDefault();savedSelection={from:view.state.selection.from,to:view.state.selection.to};onFiles(files);return true;}
        return false;
      },
      handleDrop(view,event){
        const files=Array.from(event.dataTransfer?.files||[]).filter(file=>file.type.startsWith('image/'));
        if(files.length){event.preventDefault();const position=view.posAtCoords({left:event.clientX,top:event.clientY});savedSelection={from:position?.pos||view.state.selection.from,to:position?.pos||view.state.selection.to};onFiles(files);return true;}
        return false;
      }
    },
    onUpdate:()=>updateUI(),onSelectionUpdate:()=>updateUI()
  });
  stickerPicker.innerHTML=yabolticons.map(item=>`<button type="button" data-sticker="${item.id}" aria-label="${item.label} 야볼티콘 삽입"><span class="yabolticon yabol-${item.id}" aria-hidden="true"></span><span>${item.label}</span></button>`).join('');

  function remember(){const {from,to}=editor.state.selection;savedSelection={from,to};}
  function focusChain(){const chain=editor.chain().focus();return savedSelection?chain.setTextSelection(savedSelection):chain;}
  function finish(){savedSelection=null;stickerPicker.hidden=true;tablePicker.hidden=true;root.querySelector('[data-editor="stickers"]').setAttribute('aria-expanded','false');root.querySelector('[data-editor="table"]').setAttribute('aria-expanded','false');updateUI();}
  toolbar.addEventListener('mousedown',event=>{if(event.target.closest('button')){remember();event.preventDefault();}});
  toolbar.addEventListener('click',event=>{
    const button=event.target.closest('[data-editor]');if(!button)return;
    const command=button.dataset.editor;
    if(command==='photo'){root.querySelector('#photos').click();return;}
    if(command==='preview'){onPreview();return;}
    if(command==='stickers'||command==='table'){
      remember();const picker=command==='stickers'?stickerPicker:tablePicker;const show=picker.hidden;
      finish();remember();picker.hidden=!show;button.setAttribute('aria-expanded',String(show));return;
    }
    const methods={bold:'toggleBold',italic:'toggleItalic',underline:'toggleUnderline',strike:'toggleStrike',bullet:'toggleBulletList',number:'toggleOrderedList',quote:'toggleBlockquote',rule:'setHorizontalRule',undo:'undo',redo:'redo'};
    if(methods[command]){focusChain()[methods[command]]().run();finish();}
  });
  root.querySelector('[data-editor-style]').addEventListener('mousedown',remember);
  root.querySelector('[data-editor-style]').addEventListener('change',event=>{
    const chain=focusChain();event.target.value==='paragraph'?chain.setParagraph().run():chain.setHeading({level:Number(event.target.value)}).run();finish();
  });
  stickerPicker.addEventListener('click',event=>{const button=event.target.closest('[data-sticker]');if(button){focusChain().insertContent({type:'yabolticon',attrs:{id:button.dataset.sticker}}).run();finish();}});
  root.querySelector('[data-insert-table]').addEventListener('click',()=>{
    const rows=Number(root.querySelector('#table-rows').value),cols=Number(root.querySelector('#table-columns').value);
    if(!Number.isInteger(rows)||rows<1||rows>20||!Number.isInteger(cols)||cols<1||cols>10){onError('표는 1~20행, 1~10열로 만들어 주세요.');return;}
    focusChain().insertTable({rows,cols,withHeaderRow:true}).run();finish();
  });
  root.querySelector('.table-edit-actions').addEventListener('mousedown',event=>{event.preventDefault();remember();});
  root.querySelector('.table-edit-actions').addEventListener('click',event=>{
    const command=event.target.closest('[data-table-command]')?.dataset.tableCommand;
    if(!command)return;
    if(command==='addRowAfter'||command==='addColumnAfter'){
      const {$from}=editor.state.selection;let table=null;
      for(let depth=$from.depth;depth>0;depth--)if($from.node(depth).type.name==='table')table=$from.node(depth);
      if(table&&(command==='addRowAfter'?table.childCount>=20:table.firstChild.childCount>=10)){onError('표는 최대 20행, 10열까지 사용할 수 있어요.');return;}
    }
    focusChain()[command]().run();finish();
  });
  function canonical(){
    const doc=editor.getJSON();
    function walk(node){if(node.type==='image')node.attrs={index:node.attrs.assetIndex,alt:node.attrs.alt||'본문 사진'};node.content?.forEach(walk);}
    walk(doc);return normalizeDocument(doc,100000);
  }
  function updateUI(){
    if(!editor)return;
    root.querySelector('.table-edit-actions').hidden=!editor.isActive('table');
    for(const command of ['bold','italic','underline','strike'])root.querySelector(`[data-editor="${command}"]`).setAttribute('aria-pressed',String(editor.isActive(command)));
    root.querySelector('[data-editor-style]').value=editor.isActive('heading',{level:2})?'2':editor.isActive('heading',{level:3})?'3':'paragraph';
    try{const doc=canonical();onUpdate({document:doc,text:documentText(doc),photos:imageIndexes(doc).length});}catch(error){onError(error.message);}
  }
  return {
    load(document,text,photos=[]){
      const doc=document?normalizeDocument(document,photos.length):plainDocument(text,photos);
      function walk(node){if(node.type==='image')node.attrs={src:photos[node.attrs.index],assetIndex:node.attrs.index,alt:node.attrs.alt};node.content?.forEach(walk);}
      walk(doc);editor.commands.setContent(doc,{emitUpdate:false});savedSelection=null;finish();
    },
    insertPhoto(index,src,alt){focusChain().setImage({src,assetIndex:index,alt}).run();savedSelection=null;updateUI();},
    updatePhoto(index,src){
      const transaction=editor.state.tr;
      editor.state.doc.descendants((node,pos)=>{if(node.type.name==='image'&&node.attrs.assetIndex===index)transaction.setNodeMarkup(pos,undefined,{...node.attrs,src});});
      editor.view.dispatch(transaction);
    },
    document:canonical,
    photoIndexes(){return imageIndexes(canonical());},
    focus(){editor.commands.focus();},
    clear(){editor.commands.clearContent();finish();}
  };
}
