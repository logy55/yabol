import {uploadCommunityPhoto} from './media.js?v=20261010-member-fixes';
import {accessDenied} from './access.js?v=20261010-member-fixes';
export const rosterRoles=Object.freeze({manager:'감독',coach:'코칭스태프',team_manager:'매니저',pitcher:'투수',catcher:'포수',infielder:'내야수',outfielder:'외야수'});
const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const placeholder='./assets/profile-placeholder.svg';
const imageTypes=['image/jpeg','image/png','image/webp'];
function publicPhoto(member,preview){
  if(preview&&/^data:image\/(png|jpeg|webp);base64,/.test(member.photo||''))return member.photo;
  try{const url=new URL(member.photo);return !member.photo_private&&url.protocol==='https:'&&url.hostname==='res.cloudinary.com'?url.href:null;}catch{return null;}
}
let previewRoster=[];
const sorted=members=>[...members].sort((a,b)=>(a.jersey_number??Infinity)-(b.jersey_number??Infinity)||a.name.localeCompare(b.name,'ko')||a.id.localeCompare(b.id));
const rpc=async(db,name,args)=>{const{data,error}=await db.rpc(name,args);if(error)throw error;return data;};
function rosterService(db,preview){
  if(!preview)return{list:()=>rpc(db,'get_team_roster'),save:(member,values)=>rpc(db,'save_team_roster',{p_id:member?.id||null,p_revision:member?.revision??0,p_role:values.role,p_name:values.name,p_number:values.jersey_number,p_sort_order:member?.sort_order??0,p_photo_url:values.photo||null,p_remove_photo:values.remove_photo}),remove:member=>rpc(db,'delete_team_roster',{p_id:member.id,p_revision:member.revision})};
  return{async list(){return structuredClone(previewRoster);},async save(member,values){const photo=values.remove_photo?null:values.photo||member?.photo||null;const saved={...member,...values,photo,photo_private:false,id:member?.id||crypto.randomUUID(),revision:(member?.revision??0)+1,sort_order:member?.sort_order??0};previewRoster=member?previewRoster.map(item=>item.id===member.id?saved:item):[...previewRoster,saved];return saved;},async remove(member){previewRoster=previewRoster.filter(item=>item.id!==member.id);}};
}
export function rosterContent(members,{preview=false,canEdit=false}={}){
  return `<section class="roster-page"><div class="board-heading"><div><h1>선수단</h1><p>YB Holics</p></div>${canEdit?'<div class="roster-heading-actions"><button class="primary" id="roster-add" type="button" hidden>선수 등록</button><button class="secondary" id="roster-toggle" type="button" aria-pressed="false">편집</button></div>':''}</div><p class="form-error" id="roster-error" role="alert"></p><div id="roster-groups">${rosterGroups(members,{preview,canEdit})}</div>${canEdit?rosterDialog():''}</section>`;
}
function rosterGroups(members,{preview,canEdit,editMode=false}){
  return Object.entries(rosterRoles).map(([role,label])=>{const people=sorted(members.filter(member=>member.role===role));return `<section class="roster-group" aria-labelledby="roster-${role}"><h2 id="roster-${role}">${label}</h2>${people.length?`<div class="roster-grid">${people.map(member=>{const photo=publicPhoto(member,preview);return `<figure class="roster-card"><img class="roster-photo" data-roster-id="${esc(member.id)}" src="${esc(photo||placeholder)}" width="200" height="200" alt="${esc(member.name)} ${photo?'프로필 사진':'프로필 사진 자리'}"><figcaption><span class="roster-number">No.${Number.isInteger(member.jersey_number)?member.jersey_number:'—'}</span><span class="roster-divider" aria-hidden="true">|</span><strong>${esc(member.name)}</strong></figcaption>${canEdit?`<button type="button" class="text-button roster-edit" ${editMode?'':'hidden'} data-edit-roster="${esc(member.id)}" aria-label="${esc(member.name)} 수정">수정</button>`:''}</figure>`;}).join('')}</div>`:'<p class="roster-empty">아직 등록된 인원이 없습니다.</p>'}</section>`;}).join('');
}
function rosterDialog(){return `<dialog class="dialog roster-dialog" id="roster-dialog"><div class="dialog-top"><h2 id="roster-form-title">선수 등록</h2><button class="icon-button" type="button" id="roster-close" aria-label="닫기">×</button></div><form id="roster-form"><fieldset id="roster-fields"><label>이름<input name="name" maxlength="50" required></label><div class="roster-form-row"><label>백넘버<input type="number" name="jersey_number" min="0" max="999" step="1"></label><label>포지션<select name="role">${Object.entries(rosterRoles).map(([role,label])=>`<option value="${role}">${label}</option>`).join('')}</select></label></div><label>프로필 사진<input type="file" name="photo_file" accept="image/jpeg,image/png,image/webp"></label><p class="roster-photo-help">JPG·PNG·WebP, 최대 10MB · 사진은 선수단에 공개됩니다.</p><img id="roster-photo-preview" class="roster-photo" src="${placeholder}" width="200" height="200" alt="프로필 사진 미리보기"><label class="roster-photo-remove"><input type="checkbox" name="remove_photo"> 사진 제거</label></fieldset><p class="form-error" id="roster-save-error" role="alert"></p><div class="roster-form-actions"><button class="text-button danger" id="roster-delete" type="button" hidden>선수 삭제</button><button class="primary" type="submit" id="roster-save">저장</button></div><div class="roster-delete-confirm" id="roster-delete-confirm" hidden><p>이 선수를 선수단에서 삭제할까요?</p><button type="button" class="secondary" id="roster-delete-cancel">취소</button><button type="button" class="primary" id="roster-delete-yes">삭제</button></div></form></dialog>`;}
const readFile=file=>new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(new Error('Photo read failed'));reader.readAsDataURL(file);});
async function uploadPhoto(db,config,file,signal){if(signal?.aborted)throw new Error('취소되었습니다.');return uploadCommunityPhoto(db,config,file,'yb_roster');}

export async function renderRoster(main,{preview=false,db,config,canRead,signedIn,canEdit=false,isCurrent,signal,notify=()=>{}}){
  if(!canRead){main.innerHTML=accessDenied('선수단',{signedIn});return;}
  const service=rosterService(db,preview);let members=[],editing=null,editMode=false,busy=false,request=0,previewUrl=null;const photoUrls=new Set();
  main.innerHTML='<div class="loading">선수단을 불러오고 있어요.</div>';
  try{members=await service.list();if(!Array.isArray(members))throw new Error('Invalid roster');}catch{if(isCurrent())main.innerHTML='<section class="error-panel"><strong>선수단을 불러오지 못했어요.</strong><p>잠시 후 다시 시도해 주세요.</p></section>';return;}
  if(!isCurrent())return;
  main.innerHTML=rosterContent(members,{preview,canEdit});
  const root=main.querySelector('.roster-page'),alive=()=>isCurrent()&&!signal.aborted&&main.contains(root),find=selector=>root.querySelector(selector),dialog=find('#roster-dialog'),form=find('#roster-form');
  function clearPreview(){if(previewUrl){URL.revokeObjectURL(previewUrl);previewUrl=null;}}
  function clearPhotos(){for(const url of photoUrls)URL.revokeObjectURL(url);photoUrls.clear();}
  signal.addEventListener('abort',()=>{dialog?.close();clearPreview();clearPhotos();},{once:true});
  async function loadPrivatePhotos(generation){
    if(preview||!members.some(member=>member.photo_private&&member.photo&&member.photo_post_id))return;
    const{data:{session}}=await db.auth.getSession();if(!session||!alive()||generation!==request)return;
    await Promise.all(members.filter(member=>member.photo_private&&member.photo&&member.photo_post_id).map(async member=>{
      try{
        const response=await fetch(`${config.supabaseUrl}/functions/v1/media-upload`,{method:'POST',headers:{Authorization:`Bearer ${session.access_token}`,apikey:config.supabasePublishableKey,'Content-Type':'application/json'},body:JSON.stringify({action:'read',post_id:member.photo_post_id,image:member.photo}),signal});if(!response.ok)throw new Error('Profile image access denied');
        const blob=await response.blob();if(!imageTypes.includes(blob.type))throw new Error('Unsupported image');if(!alive()||generation!==request)return;
        const img=[...root.querySelectorAll('[data-roster-id]')].find(el=>el.dataset.rosterId===member.id);if(!img)return;
        const url=URL.createObjectURL(blob);photoUrls.add(url);img.src=url;img.alt=`${member.name} 프로필 사진`;
      }catch{/* Keep the placeholder if access has changed. */}
    }));
  }
  async function refresh(){const generation=++request;find('#roster-error').textContent='';try{const data=await service.list();if(!Array.isArray(data))throw new Error('Invalid roster');if(!alive()||generation!==request)return;members=data;clearPhotos();find('#roster-groups').innerHTML=rosterGroups(members,{preview,canEdit,editMode});void loadPrivatePhotos(generation);}catch{if(alive()&&generation===request)find('#roster-error').textContent='변경은 저장했지만 목록을 새로 불러오지 못했어요. 새로고침해 주세요.';}}
  function setBusy(value){busy=value;find('#roster-fields').disabled=value;for(const id of ['roster-close','roster-save','roster-delete','roster-delete-cancel','roster-delete-yes','roster-toggle','roster-add'])find(`#${id}`).disabled=value;}
  function open(member=null){if(busy||!canEdit||!editMode)return;editing=member;form.reset();clearPreview();form.elements.name.value=member?.name||'';form.elements.jersey_number.value=member?.jersey_number??'';form.elements.role.value=member?.role||'pitcher';find('#roster-form-title').textContent=member?'선수 수정':'선수 등록';find('#roster-save-error').textContent='';find('#roster-delete').hidden=!member;find('#roster-delete-confirm').hidden=true;const card=[...root.querySelectorAll('[data-roster-id]')].find(el=>el.dataset.rosterId===member?.id);find('#roster-photo-preview').src=card?.src||placeholder;dialog.showModal();}
  if(form){
    find('#roster-toggle').onclick=()=>{if(busy)return;editMode=!editMode;find('#roster-toggle').textContent=editMode?'편집 종료':'편집';find('#roster-toggle').setAttribute('aria-pressed',String(editMode));find('#roster-add').hidden=!editMode;root.querySelectorAll('[data-edit-roster]').forEach(button=>{button.hidden=!editMode;});};find('#roster-add').onclick=()=>open();find('#roster-close').onclick=()=>dialog.close();dialog.onclose=clearPreview;dialog.oncancel=event=>{if(busy)event.preventDefault();};
    form.elements.photo_file.onchange=()=>{clearPreview();find('#roster-save-error').textContent='';const file=form.elements.photo_file.files[0];if(!file)return;if(!imageTypes.includes(file.type)||file.size>10*1024*1024||file.size<1){form.elements.photo_file.value='';find('#roster-save-error').textContent='JPG·PNG·WebP 사진을 10MB 이하로 선택해 주세요.';return;}form.elements.remove_photo.checked=false;previewUrl=URL.createObjectURL(file);find('#roster-photo-preview').src=previewUrl;};
    form.elements.remove_photo.onchange=()=>{if(form.elements.remove_photo.checked){form.elements.photo_file.value='';clearPreview();find('#roster-photo-preview').src=placeholder;}else{const card=[...root.querySelectorAll('[data-roster-id]')].find(el=>el.dataset.rosterId===editing?.id);find('#roster-photo-preview').src=card?.src||placeholder;}};
    find('#roster-delete').onclick=()=>{find('#roster-delete-confirm').hidden=false;};find('#roster-delete-cancel').onclick=()=>{find('#roster-delete-confirm').hidden=true;};
    find('#roster-delete-yes').onclick=async()=>{if(busy||!editing||!editMode||!canEdit)return;setBusy(true);try{await service.remove(editing);if(!alive())return;dialog.close();notify('선수를 삭제했어요.');await refresh();}catch{if(alive())find('#roster-save-error').textContent='삭제하지 못했어요. 새로고침 후 다시 시도해 주세요.';}finally{if(alive())setBusy(false);}};
    form.onsubmit=async event=>{event.preventDefault();if(busy||!editMode||!canEdit)return;const values={name:form.elements.name.value.trim(),role:form.elements.role.value,jersey_number:form.elements.jersey_number.value===''?null:Number(form.elements.jersey_number.value),remove_photo:form.elements.remove_photo.checked,photo:null};if(!values.name)return;const file=form.elements.photo_file.files[0];setBusy(true);find('#roster-save-error').textContent='';try{if(file){values.photo=preview?await readFile(file):await uploadPhoto(db,config,file,signal);if(!alive())return;}await service.save(editing,values);if(!alive())return;dialog.close();notify('선수 정보를 저장했어요.');await refresh();}catch(error){if(alive())find('#roster-save-error').textContent=/Roster changed/.test(error?.message||'')?'다른 사람이 먼저 수정했어요. 새로고침 후 다시 편집해 주세요.':'저장하지 못했어요. 입력 내용과 편집 권한을 확인하고 다시 시도해 주세요.';}finally{if(alive())setBusy(false);}};
  }
  root.addEventListener('click',event=>{const edit=event.target.closest('[data-edit-roster]');if(edit)open(members.find(member=>member.id===edit.dataset.editRoster));});
  void loadPrivatePhotos(request);
}
