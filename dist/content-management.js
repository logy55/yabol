const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export async function deleteContent(db,kind,id,{notify,onChanged}){
  if(!window.confirm(`${kind==='post'?'게시글':'댓글'}을 삭제할까요? 내 정보의 삭제한 글·댓글에서 복구할 수 있습니다.`))return;
  const{error}=await db.rpc('manage_deleted_content',{p_kind:kind,p_id:id,p_restore:false});
  if(error){notify('삭제하지 못했어요. 권한과 로그인 상태를 확인해 주세요.');return;}
  await onChanged();notify('삭제했어요. 내 정보에서 복구할 수 있습니다.');
}

export function bindCommentActions(root,comments,{db,canManage,notify,onChanged}){
  root.onclick=async event=>{
    const button=event.target.closest('[data-comment-action]');if(!button)return;
    const comment=comments.find(c=>c.id===button.dataset.id);if(!comment||!canManage(comment))return;
    const item=button.closest('.comment');
    if(button.dataset.commentAction==='delete'){button.disabled=true;try{await deleteContent(db,'comment',comment.id,{notify,onChanged});}finally{button.disabled=false;}return;}
    item.querySelector('.comment-content').hidden=true;item.querySelector('.comment-controls').hidden=true;
    const form=document.createElement('form');form.className='comment-edit-form';
    form.innerHTML=`<label>댓글 수정<textarea rows="3" maxlength="2000" required>${escapeHtml(comment.body)}</textarea></label><div><button class="primary" type="submit">저장</button><button class="secondary" type="button" data-cancel>취소</button></div><p class="form-error" role="alert"></p>`;
    item.append(form);form.querySelector('textarea').focus();
    form.querySelector('[data-cancel]').onclick=()=>{form.remove();item.querySelector('.comment-content').hidden=false;item.querySelector('.comment-controls').hidden=false;};
    form.onsubmit=async e=>{
      e.preventDefault();const save=form.querySelector('[type=submit]');save.disabled=true;
      try{
        const body=form.querySelector('textarea').value.trim();if(!body)throw new Error('empty');
        const{data,error}=await db.from('comments').update({body}).eq('id',comment.id).eq('updated_at',comment.updated_at).select('id').single();
        if(error||!data)throw error||new Error('changed');await onChanged();notify('댓글을 수정했어요.');
      }catch{form.querySelector('.form-error').textContent='저장하지 못했어요. 다른 곳에서 수정됐거나 권한이 바뀌었을 수 있습니다. 새로고침 후 확인해 주세요.';}
      finally{save.disabled=false;}
    };
  };
}

export async function renderTrash(root,{db,isCurrent,notify,onChanged}){
  root.innerHTML='<div class="loading">삭제한 글·댓글을 불러오고 있어요.</div>';
  const{data,error}=await db.rpc('get_deleted_content');if(!isCurrent())return;
  if(error){root.innerHTML='<div class="error-panel">삭제한 내용을 불러오지 못했어요.</div>';return;}
  root.innerHTML=`<section><div class="board-heading"><h1>삭제한 글·댓글</h1><a class="secondary" href="#/account">내 정보</a></div>${data.length?`<div class="deleted-content-list">${data.map(item=>`<div class="deleted-content-item"><div><span>${item.kind==='post'?'게시글':'댓글'} · ${new Date(item.deleted_at).toLocaleString('ko-KR')}</span><p>${escapeHtml(item.label)}</p></div><button class="secondary" data-restore="${item.id}" data-kind="${item.kind}">복구</button></div>`).join('')}</div>`:'<div class="empty">삭제한 글·댓글이 없습니다.</div>'}</section>`;
  root.onclick=async e=>{
    const button=e.target.closest('[data-restore]');if(!button)return;button.disabled=true;
    const{error}=await db.rpc('manage_deleted_content',{p_kind:button.dataset.kind,p_id:button.dataset.restore,p_restore:true});
    if(error){notify('복구하지 못했어요. 게시판 권한을 확인해 주세요.');button.disabled=false;return;}
    await onChanged();if(isCurrent())await renderTrash(root,{db,isCurrent,notify,onChanged});notify('복구했어요.');
  };
}
