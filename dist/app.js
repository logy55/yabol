import {deleteContent,bindCommentActions,renderTrash} from './content-management.js?v=20261010-member-fixes2';
import {uploadCommunityPhoto} from './media.js?v=20261010-member-fixes';
import {recruitmentPanel,bindRecruitment,previewRecruitmentComments,updateRecruitmentMember} from './recruitment.js?v=20261010-member-fixes';
import { boards, galleryCategories, freeCategories, staffCategories } from './sample.js?v=20261010-member-fixes';
import './navigation.js?v=20261010-member-fixes';
import {renderTool} from './tools.js?v=20261010-member-fixes';
import {accountBar, accountView, accountActions} from './account.js?v=20261010-member-fixes';
import {restrictionActive,restrictionView} from './restrictions.js?v=20261010-member-fixes';
import {accessDenied} from './access.js?v=20261010-member-fixes';
import {renderCalendar} from './calendar.js?v=20261010-member-fixes';
import {renderRoster} from './roster.js?v=20261010-member-fixes';
import {canManageMembers,effectivePermission,boardMenus,postMenu} from './admin-model.js?v=20261010-member-fixes';
import {teamChoices, memberName} from './teams.js?v=20261010-member-fixes';
import {requestMembership} from './membership.js?v=20261010-member-fixes';
import {renderAdmin} from './admin.js?v=20261010-member-fixes';
import {createPostEditor} from './post-editor.js?v=20261010-member-fixes';
import {normalizeDocument,imageIndexes,documentText,remapDocumentPhotos,renderDocument} from './rich-body.js?v=20261010-member-fixes';
import {yabolticons,yabolticonHTML,renderYabolText} from './yabolticons.js?v=20261010-member-fixes';

const config=window.COMMUNITY_CONFIG;
document.querySelector('#copyright-year').textContent=String(new Date().getFullYear());
const main=document.querySelector('#main');
const ready=Boolean(config.supabaseUrl&&config.supabasePublishableKey);
let posts=[],db=null,user=null,authMode='login',photoAssets=[],photoUrls=[],toastTimer,sort=location.hash.startsWith('#/best')?'popular':'latest',page=1;
let memberProfile=null,currentPost=null;
const accountUser=()=>user?{...user,user_metadata:{...user.user_metadata,...memberProfile,staff_role:memberProfile?.staff_role||'member',yb_role:memberProfile?.yb_role||'member',is_yb_member:memberProfile?.is_yb_member===true,is_admin:memberProfile?.is_admin===true}}:null;
const displayedAccount=()=>accountUser();
let allowedBoards=ready?new Set():new Set(Object.keys(boards).filter(key=>!boards[key].restricted)),writableBoards=ready?new Set():new Set(['free','gallery']),accessLoading=ready,authEpoch=0,renderEpoch=0,privatePhotoUrls=[],photoController=null;
let menuPermissions={},restrictionTimer,restrictionPreviewProfile=null;
const canReadMenu=menu=>ready?menuPermissions[menu]?.read===true:effectivePermission(displayedAccount()?.user_metadata||null,menu)!=='deny';
const canWriteMenu=menu=>ready?menuPermissions[menu]?.write===true:effectivePermission(displayedAccount()?.user_metadata||null,menu)==='write';
const canReadBoard=(key,category)=>Boolean(boards[key])&&(category!==undefined||key==='yb'?canReadMenu(postMenu(key,category)):(boardMenus[key]||[]).some(canReadMenu));
const canWriteBoard=(key,category)=>Boolean(boards[key])&&(category!==undefined||key==='yb'?canWriteMenu(postMenu(key,category)):(boardMenus[key]||[]).some(canWriteMenu));
const canManageContent=post=>Boolean(displayedAccount())&&canWriteBoard(post.board,post.category)&&(displayedAccount().id===post.author_id||canManageMembers(memberProfile));
const visiblePosts=()=>posts.filter(post=>canReadBoard(post.board,post.category));
const icons={like:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 10v11H3V10zm0 0 5-7c1-1 3 0 3 2l-1 5h5c2 0 2 2 2 3l-2 8H7"></path></svg>'};
const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const dateText=value=>{const elapsed=Math.max(0,Date.now()-new Date(value).getTime());if(elapsed<3600000)return `${Math.max(1,Math.floor(elapsed/60000))}분 전`;if(elapsed<86400000)return `${Math.floor(elapsed/3600000)}시간 전`;return new Date(value).toLocaleDateString('ko-KR',{month:'2-digit',day:'2-digit'});};
const safeImage=value=>{try{const url=new URL(value);return url.protocol==='https:'&&url.hostname==='res.cloudinary.com'?url.href:'';}catch{return '';}};
function toast(message){const el=document.querySelector('#toast');el.textContent=message;el.hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.hidden=true,4500);}
const topicKey=post=>post.board==='free'?(Object.hasOwn(freeCategories,post.category)?post.category:'chat'):null;
const topicLabel=post=>topicKey(post)?freeCategories[topicKey(post)]:null;
function list(items,compact=false){if(!items.length)return '<div class="empty"><strong>아직 게시글이 없어요.</strong>첫 이야기를 나눠 주세요.</div>';return `<div class="post-list${compact?' compact':''}">${items.map(post=>`<a class="post-row" href="#/post/${encodeURIComponent(post.id)}"><span class="board-tag ${esc(post.board)}" ${topicKey(post)?`data-topic="${topicKey(post)}"`:''}>${esc(topicLabel(post)||(post.board==='staff'?staffCategories[post.category]:null)||boards[post.board]?.name||'게시판')}</span><span class="row-title">${compact&&topicLabel(post)?`<span class="inline-topic" data-topic="${topicKey(post)}">[${esc(topicLabel(post))}]</span>`:''}${esc(post.title)}<span class="comment-count">${post.commentCount||''}</span>${post.images?.length?'<span class="photo-badge">▧</span>':''}${Date.now()-new Date(post.created_at).getTime()<10800000?'<span class="new-badge">N</span>':''}</span><span class="row-author">${memberName(post.author,post.team,post.region,post.staff_role,post.is_yb_member)}</span><time class="row-time" datetime="${esc(post.created_at)}">${dateText(post.created_at)}</time></a>`).join('')}</div>`;}
function home(){const readable=visiblePosts(),notice=readable.find(p=>p.board==='notice'&&p.is_notice),popular=readable.filter(p=>!(p.board==='notice'&&p.is_notice)).sort((a,b)=>b.likes-a.likes).slice(0,8);main.innerHTML=`<div class="notice-strip"><strong>공지</strong>${notice?`<a href="#/post/${encodeURIComponent(notice.id)}">${esc(notice.title)}</a><time>${dateText(notice.created_at)}</time>`:'<span>등록된 공지사항이 없습니다.</span>'}</div><div id="home-banner-slot" hidden></div><section class="home-popular"><div class="section-top"><h1>전체 인기글</h1><div class="section-actions"><a class="more-link" href="#/best">전체 보기</a><button class="primary" data-write>글쓰기</button></div></div>${list(popular)}</section>`;}

function accessPanel(key,category){
  if(accessLoading){main.innerHTML='<div class="loading">접근 권한을 확인하고 있어요.</div>';return;}
  const title=key==='staff'&&category?staffCategories[category]:key==='gallery'&&category?galleryCategories[category]:boards[key].name;
  main.innerHTML=accessDenied(title,{signedIn:Boolean(displayedAccount())});
}
function boardView(path){
  const key=path[1],board=boards[key];
  if(path[0]==='board'&&['info','question'].includes(key)){location.replace(`#/board/free?category=${key}`);return;}
  if(path[0]==='board'&&!board){main.innerHTML='<div class="empty"><strong>게시판을 찾을 수 없어요.</strong><a href="#/">홈으로</a></div>';return;}
  const requested=new URLSearchParams(location.hash.split('?')[1]).get('category');
  const categories=key==='gallery'?galleryCategories:key==='free'?freeCategories:key==='staff'?staffCategories:null;
  const category=categories&&Object.hasOwn(categories,requested)?requested:null;
  if(board&&!canReadBoard(key,category??undefined)){accessPanel(key,category);return;}
  let title=category&&key!=='free'?categories[category]:board?.name||'전체글',description=board?.description??'모든 게시판의 이야기를 모아 봅니다.',items=visiblePosts();
  if(path[0]==='best'){title='인기글';description='추천을 많이 받은 이야기';items=items.filter(p=>!p.is_notice);}
  else if(path[0]==='search'){const term=new URLSearchParams(location.hash.split('?')[1]).get('q')||'';title='검색 결과';description=`‘${term}’에 대한 게시글`;items=items.filter(p=>(p.title+' '+p.body).toLowerCase().includes(term.toLowerCase()));}
  else if(board){items=items.filter(p=>p.board===key&&(!category||p.category===category));}
  items=[...items].sort((a,b)=>sort==='popular'?b.likes-a.likes:new Date(b.created_at)-new Date(a.created_at));
  const max=Math.max(1,Math.ceil(items.length/20));page=Math.min(page,max);
  main.innerHTML=`<div class="board-heading"><div><h1>${esc(title)}</h1>${description?`<p>${esc(description)}</p>`:''}</div><button class="primary" data-write ${ready&&user&&(board?!canWriteBoard(key,category??undefined):!writableBoards.size)?'disabled title="글쓰기 권한이 없습니다"':''}>글쓰기</button></div>${categories&&key==='free'?`<nav class="category-tabs" aria-label="${key==='free'?'말머리':key==='staff'?'운영진 하위 게시판':'사진 분류'}"><a href="#/board/${key}" class="${!category?'active':''}" ${!category?'aria-current="page"':''}>${key==='gallery'?'전체 사진':'전체'}</a>${Object.entries(categories).filter(([value])=>key==='free'||canReadMenu(postMenu(key,value))).map(([value,label])=>`<a href="#/board/${key}?category=${value}" ${key==='free'?`data-topic="${value}"`:''} class="${category===value?'active':''}" ${category===value?'aria-current="page"':''}>${label}</a>`).join('')}</nav>`:''}<div class="board-toolbar"><button data-sort="latest" class="${sort==='latest'?'active':''}">최신순</button><button data-sort="popular" class="${sort==='popular'?'active':''}">추천순</button><span class="more-link">${items.length.toLocaleString()}개 글</span></div>${list(items.slice((page-1)*20,page*20))}<div class="page-controls"><button data-page="-1" ${page===1?'disabled':''}>이전</button><span>${page} / ${max}</span><button data-page="1" ${page===max?'disabled':''}>다음</button></div>`;
}
function clearPrivatePhotos(){photoController?.abort();photoController=null;privatePhotoUrls.forEach(URL.revokeObjectURL);privatePhotoUrls=[];}
async function loadPrivatePhotos(post,epoch,renderId){
  photoController=new AbortController();const signal=photoController.signal;
  const{data:{session}}=await db.auth.getSession();
  if(!session||epoch!==authEpoch||renderId!==renderEpoch)return;
  await Promise.all((post.images||[]).map(async(image,index)=>{
    try{
      const response=await fetch(`${config.supabaseUrl}/functions/v1/media-upload`,{method:'POST',headers:{Authorization:`Bearer ${session.access_token}`,apikey:config.supabasePublishableKey,'Content-Type':'application/json'},body:JSON.stringify({action:'read',post_id:post.id,image}),signal});
      if(!response.ok)throw new Error('Image access denied');
      const blob=await response.blob();
      if(!['image/jpeg','image/png','image/webp'].includes(blob.type))throw new Error('Unsupported image');
      if(signal.aborted||epoch!==authEpoch||renderId!==renderEpoch||!canReadBoard(post.board,post.category))return;
      const holders=main.querySelectorAll(`[data-private-photo="${index}"]`);if(!holders.length)return;
      const url=URL.createObjectURL(blob);privatePhotoUrls.push(url);holders.forEach(holder=>{const img=document.createElement('img');img.src=url;img.alt='게시글에 첨부한 사진';holder.replaceWith(img);});
    }catch{if(!signal.aborted&&epoch===authEpoch&&renderId===renderEpoch){main.querySelectorAll(`[data-private-photo="${index}"]`).forEach(holder=>holder.textContent='사진을 불러오지 못했어요.');}}
  }));
}
function postBodyPresentation(post){
  try{if(post.body_doc){const doc=normalizeDocument(post.body_doc,(post.images||[]).length);return{html:renderDocument(doc,post.images||[],{restricted:boards[post.board].restricted}),rich:true,used:imageIndexes(doc)};}}catch{}
  return{html:esc(post.body),rich:false,used:[]};
}
function remainingPostPhotos(post,used){return (post.images||[]).map((url,index)=>used.includes(index)?'':boards[post.board].restricted?`<div class="loading" data-private-photo="${index}">사진을 불러오는 중입니다.</div>`:safeImage(url)?`<img src="${esc(safeImage(url))}" alt="게시글에 첨부한 사진" loading="lazy">`:'').join('');}
async function postView(id,epoch,renderId){let post=visiblePosts().find(p=>p.id===id);if(!post&&db){const{data,error}=await db.from('post_feed').select('*').eq('id',id).maybeSingle();if(error)throw error;if(data)post=normalize(data);}if(epoch!==authEpoch||renderId!==renderEpoch)return;if(post&&!canManageContent(post)){toast('이 글을 수정할 권한이 없습니다.');return;}if(post&&!canReadBoard(post.board,post.category)){accessPanel(post.board,post.category);return;}if(!post){main.innerHTML='<div class="empty"><strong>게시글을 찾을 수 없어요.</strong><a href="#/all">전체글 보기</a></div>';return;}currentPost=post;const bodyPresentation=postBodyPresentation(post);main.innerHTML=`<article class="article"><a class="breadcrumbs" href="#/board/${esc(post.board)}">${esc(boards[post.board]?.name||'게시판')}</a><h1>${topicLabel(post)?`<span class="article-topic" data-topic="${topicKey(post)}">[${esc(topicLabel(post))}]</span> `:''}${esc(post.title)}</h1><div class="article-meta"><strong class="member-identity">${memberName(post.author,post.team,post.region,post.staff_role,post.is_yb_member)}</strong><time>${new Date(post.created_at).toLocaleString('ko-KR')}</time></div><div class="article-body${bodyPresentation.rich?' rich-body':''}">${bodyPresentation.html}</div><div class="article-images">${remainingPostPhotos(post,bodyPresentation.used)}</div><div class="article-actions">${canManageContent(post)?'<button class="secondary" data-edit>글 수정</button><button class="secondary danger-button" data-delete-post>글 삭제</button>':''}<button class="like-button" id="like-button">${icons.like} 추천 <span>${post.likes||0}</span></button><a class="secondary" href="#/board/${esc(post.board)}">목록</a></div>${post.board==='recruit'?recruitmentPanel():''}<section class="comment-section"><h2>댓글 <span id="comment-count">${post.commentCount||0}</span></h2><div id="comments">${ready?'<div class="loading">댓글을 불러오는 중입니다.</div>':'<div class="empty">댓글 등록은 서비스 연결 후 사용할 수 있어요.</div>'}</div><form id="comment-form" class="comment-form"><label for="comment-body">${user?(canWriteBoard(post.board,post.category)?'댓글을 남겨 주세요':'읽기만 허용된 게시판입니다.'):'댓글을 쓰려면 로그인해 주세요'}</label><textarea id="comment-body" name="body" rows="3" maxlength="2000" placeholder="서로를 존중하는 이야기를 나눠 주세요" required></textarea><div class="comment-sticker-tools"><button type="button" class="secondary" id="comment-yabol-button" aria-expanded="false" aria-controls="comment-yabol-picker">야볼티콘</button><div id="comment-yabol-picker" class="yabol-picker" hidden></div></div><p class="form-error" id="comment-error" role="alert"></p><button class="primary" type="submit" ${!ready||user&&!canWriteBoard(post.board,post.category)?'disabled':''}>댓글 등록</button></form></section></article>`;setupCommentStickers();if(post.board==='recruit')void bindRecruitment(main,{post,actor:displayedAccount(),db,canRead:canReadBoard('recruit'),isCurrent:()=>epoch===authEpoch&&renderId===renderEpoch,onAuth:()=>openAuth(),onChanged:async()=>{await loadComments(post.id,epoch,renderId);if(db)await loadPosts(epoch);else post.commentCount=previewRecruitmentComments(post.id).length;}});document.querySelector('#like-button').onclick=()=>like(post);document.querySelector('[data-edit]')?.addEventListener('click',()=>openWrite(post));document.querySelector('[data-delete-post]')?.addEventListener('click',()=>deleteContent(db,'post',post.id,{notify:toast,onChanged:async()=>{await loadPosts();location.hash=`#/board/${post.board}`;await render();}}));document.querySelector('#comment-form').onsubmit=async event=>{event.preventDefault();if(!user){openAuth();return;}if(!canWriteBoard(post.board,post.category)){toast('이 게시판은 읽기만 허용됩니다.');return;}const form=event.currentTarget,button=form.querySelector('button[type="submit"]');button.disabled=true;try{const{error}=await db.from('comments').insert({post_id:post.id,author_id:user.id,body:new FormData(form).get('body').trim()});if(error)throw error;form.reset();await loadComments(post.id);await loadPosts();toast('댓글을 등록했어요.');}catch{document.querySelector('#comment-error').textContent='댓글을 저장하지 못했어요. 입력한 내용을 확인하고 다시 시도해 주세요.';}finally{button.disabled=false;}};if(db){if(boards[post.board].restricted)void loadPrivatePhotos(post,epoch,renderId);await loadComments(post.id,epoch,renderId);}else if(post.board==='recruit')await loadComments(post.id,epoch,renderId);}
function setupCommentStickers(){
  const button=document.querySelector('#comment-yabol-button'),picker=document.querySelector('#comment-yabol-picker'),input=document.querySelector('#comment-body');let selection=null;
  picker.innerHTML=yabolticons.map(item=>`<button type="button" data-comment-sticker="${item.id}" aria-label="${item.label} 야볼티콘 삽입">${yabolticonHTML(item.id)}<span>${item.label}</span></button>`).join('');
  button.onclick=()=>{selection={start:input.selectionStart,end:input.selectionEnd};picker.hidden=!picker.hidden;button.setAttribute('aria-expanded',String(!picker.hidden));};
  picker.onclick=event=>{const selected=event.target.closest('[data-comment-sticker]');if(!selected)return;const token=`[야볼티콘:${selected.dataset.commentSticker}]`;if(input.value.length-(selection.end-selection.start)+token.length>2000){toast('댓글은 2,000자까지 입력할 수 있어요.');return;}input.setRangeText(token,selection.start,selection.end,'end');picker.hidden=true;button.setAttribute('aria-expanded','false');input.focus();};
}
async function loadComments(id,epoch=authEpoch,renderId=renderEpoch){
  const{data,error}=db?await db.from('comment_feed').select('*').eq('post_id',id).order('created_at'):{data:previewRecruitmentComments(id),error:null};
  if(epoch!==authEpoch||renderId!==renderEpoch||location.hash!==`#/post/${id}`||!document.querySelector('#comments'))return;
  const root=document.querySelector('#comments');
  if(error){root.innerHTML='<p class="form-error">댓글을 불러오지 못했어요.</p>';return;}
  const post=currentPost?.id===id?currentPost:posts.find(p=>p.id===id),canManage=c=>Boolean(db&&post&&canWriteBoard(post.board,post.category)&&(c.author_id===user?.id||canManageMembers(memberProfile)));
  document.querySelector('#comment-count').textContent=data.length;
  root.innerHTML=data.length?data.map(c=>`<div class="comment"><div class="comment-header"><strong class="member-identity">${memberName(c.nickname,c.team,c.region,c.staff_role,c.is_yb_member)}</strong><time>${dateText(c.created_at)}</time>${canManage(c)?`<div class="comment-controls"><button class="text-button" data-comment-action="edit" data-id="${esc(c.id)}">수정</button><button class="text-button" data-comment-action="delete" data-id="${esc(c.id)}">삭제</button></div>`:''}</div><p class="comment-content">${renderYabolText(c.body)}</p></div>`).join(''):'<div class="empty">첫 댓글을 남겨 주세요.</div>';
  if(db)bindCommentActions(root,data,{db,canManage,notify:toast,onChanged:async()=>{await loadComments(id,epoch,renderId);await loadPosts(epoch);}});
}

async function like(post){if(!db){toast('추천 기능은 커뮤니티 연결 후 사용할 수 있어요.');return;}if(!user){openAuth();return;}const button=document.querySelector('#like-button');button.disabled=true;try{const{data:existing,error:readError}=await db.from('likes').select('post_id').eq('post_id',post.id).eq('user_id',user.id).maybeSingle();if(readError)throw readError;const result=existing?await db.from('likes').delete().eq('post_id',post.id).eq('user_id',user.id):await db.from('likes').insert({post_id:post.id,user_id:user.id});if(result.error)throw result.error;await loadPosts();await render();}catch{toast('추천을 저장하지 못했어요. 잠시 뒤 다시 시도해 주세요.');}finally{button.disabled=false;}}
function normalize(p){return{...p,author:p.nickname||'회원',likes:Number(p.like_count||0),commentCount:Number(p.comment_count||0)};}
async function loadPosts(epoch=authEpoch){if(!user||!memberProfile){posts=[];return;}const{data,error}=await db.from('post_feed').select('*').order('created_at',{ascending:false}).limit(500);if(epoch!==authEpoch)return;if(error)throw error;posts=data.map(normalize).filter(p=>canReadBoard(p.board,p.category));}
async function adminMemberSaved(updated,{preview}){
  if(preview){updateRecruitmentMember(updated);posts=posts.map(post=>post.preview_member_id===updated.id?{...post,team:updated.team,staff_role:updated.staff_role,is_yb_member:updated.is_yb_member}:post);updateAccount();return;}
  if(updated.id===user?.id){const{data,error}=await db.rpc('get_my_membership');if(!error&&data){memberProfile=trustedMembership(data);updateAccount();}}
  try{await loadPosts();}catch{toast('설정은 저장됐지만 게시글 표시를 갱신하지 못했어요. 새로고침해 주세요.');}
}
async function render(){const epoch=authEpoch,renderId=++renderEpoch;clearPrivatePhotos();currentPost=null;const path=(location.hash.slice(2).split('?')[0]||'').split('/').filter(Boolean);try{main.onclick=null;const member=displayedAccount()?.user_metadata;if(ready&&(accessLoading||!user||!memberProfile)){main.innerHTML=accessLoading?'<div class="loading">회원 정보를 확인하고 있어요.</div>':'<section class="access-panel"><h1>로그인이 필요합니다.</h1><p>관리자 승인을 받은 회원만 이용할 수 있습니다.</p><div class="access-actions"><button class="primary" data-auth>로그인</button><button class="secondary" data-signup>회원가입</button></div></section>';return;}if(restrictionActive(member)){main.innerHTML=restrictionView(member);document.querySelector('#write-dialog').close();main.querySelector('#restriction-check').onclick=()=>ready?refreshIdentity(user).catch(()=>toast('제한 상태를 확인하지 못했어요.')):render();return;}if(path[0]==='admin'&&path[1]==='restriction'){main.innerHTML=canManageMembers(member)&&restrictionPreviewProfile?restrictionView(restrictionPreviewProfile,{preview:true}):'<section class="access-panel"><h1>이용 제한 안내</h1><p>회원관리에서 안내를 볼 회원을 선택해 주세요.</p><a class="secondary" href="#/admin">회원관리로 돌아가기</a></section>';return;}if(path[0]==='admin')await renderAdmin(main,{db,preview:!ready,canAdmin:canManageMembers(displayedAccount()?.user_metadata),isAdmin:displayedAccount()?.user_metadata?.is_admin===true,actorId:displayedAccount()?.id,isCurrent:()=>epoch===authEpoch&&renderId===renderEpoch,onSaved:adminMemberSaved,notify:toast,onRestrictionPreview:profile=>{restrictionPreviewProfile=structuredClone(profile);location.hash='#/admin/restriction';}});else if(path[0]==='yb'&&path[1]==='roster'){photoController=new AbortController();await renderRoster(main,{preview:!ready,db,config,canRead:canReadMenu('yb_roster'),signedIn:Boolean(displayedAccount()),canEdit:canWriteMenu('yb_roster'),notify:toast,isCurrent:()=>epoch===authEpoch&&renderId===renderEpoch,signal:photoController.signal});}else if(path[0]==='yb'&&path[1]==='calendar')await renderCalendar(main,{db,preview:!ready,canRead:canReadMenu('yb_calendar'),signedIn:Boolean(displayedAccount()),canEdit:canWriteMenu('yb_calendar'),isCurrent:()=>epoch===authEpoch&&renderId===renderEpoch,notify:toast});else if(path[0]==='trash')await renderTrash(main,{db,isCurrent:()=>epoch===authEpoch&&renderId===renderEpoch,notify:toast,onChanged:()=>loadPosts(epoch)});else if(path[0]==='account')main.innerHTML=accountView(displayedAccount(),{preview:!ready});else if(path[0]==='tools'){photoController=new AbortController();await renderTool(main,path[1],{db,actor:displayedAccount(),isCurrent:()=>epoch===authEpoch&&renderId===renderEpoch,onAuth:()=>openAuth(),signal:photoController.signal,notify:toast});}else if(path[0]==='post')await postView(decodeURIComponent(path[1]||''),epoch,renderId);else if(path.length===0)home();else boardView(path);}catch{if(epoch!==authEpoch||renderId!==renderEpoch)return;main.innerHTML='<div class="error-panel"><strong>게시글을 불러오지 못했어요.</strong><p>잠시 뒤 새로고침해 주세요.</p><button class="secondary" id="retry-load">다시 시도</button></div>';document.querySelector('#retry-load').onclick=async()=>{try{await loadPosts();await render();}catch{toast('아직 연결할 수 없어요.');}};}}
function openAuth(mode='login'){
  authMode=mode;const signup=mode==='signup',form=document.querySelector('#auth-form');
  document.querySelector('#auth-title').textContent=signup?'회원가입':'로그인';
  document.querySelector('#password-confirm-label').hidden=!signup;form.elements.password_confirmation.required=signup;form.elements.password_confirmation.disabled=!signup;form.elements.password_confirmation.setCustomValidity('');
  document.querySelector('#yb-request-label').hidden=!signup;form.elements.yb_requested.disabled=!signup;
  document.querySelector('#nickname-label').hidden=!signup;form.elements.nickname.required=signup;
  document.querySelector('#region-label').hidden=!signup;form.elements.region.required=signup;
  const teamFieldset=document.querySelector('#team-fieldset');teamFieldset.hidden=!signup;teamFieldset.disabled=!signup;
  document.querySelector('#approval-notice').hidden=!signup;
  form.elements.password.autocomplete=signup?'new-password':'current-password';
  document.querySelector('#auth-submit').textContent=signup?'가입 신청':'로그인';document.querySelector('#auth-submit').disabled=!db;
  document.querySelector('#auth-error').textContent='';document.querySelector('#switch-auth').textContent=signup?'로그인으로 전환':'회원가입으로 전환';
  document.querySelector('#auth-dialog').showModal();
}
let editPhotoController=null,editorGeneration=0;
const writeError=message=>{document.querySelector('#write-error').textContent=message;};
const postEditor=createPostEditor({root:document.querySelector('#editor-root'),onFiles:addEditorPhotos,onError:writeError,onPreview:showWritePreview,onUpdate:({text,photos})=>{
  document.querySelector('#editor-count').textContent=`${text.length.toLocaleString()} / 10,000자 · 사진 ${photos}/5`;
}});
function clearPhotos(){editorGeneration++;editPhotoController?.abort();editPhotoController=null;photoUrls.forEach(URL.revokeObjectURL);photoUrls=[];photoAssets=[];document.querySelector('#photos').value='';document.querySelector('#preview-dialog').close();}
function addEditorPhotos(files){
  try{if(postEditor.photoIndexes().length+files.length>5)throw new Error('사진은 최대 5장까지 넣을 수 있어요.');
    if(files.some(file=>!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>10*1024*1024))throw new Error('10MB 이하의 JPG·PNG·WEBP 사진을 선택해 주세요.');
    for(const file of files){const url=URL.createObjectURL(file);photoUrls.push(url);const index=photoAssets.push({file,url})-1;postEditor.insertPhoto(index,url,file.name.slice(0,200));}
    writeError('');
  }catch(error){writeError(error.message);}
}
function showWritePreview(){try{const doc=postEditor.document(),indexes=imageIndexes(doc);if(indexes.some(index=>!photoAssets[index]))throw new Error('사진을 다시 삽입해 주세요.');document.querySelector('#preview-title').textContent=document.querySelector('#write-form').elements.title.value.trim()||'제목 없는 글';document.querySelector('#rich-preview').innerHTML=renderDocument(doc,photoAssets.map(asset=>asset.url),{resolveImage:url=>url});document.querySelector('#preview-dialog').showModal();}catch(error){writeError(error.message);}}
async function loadEditPhotos(post){
  const generation=editorGeneration,epoch=authEpoch;editPhotoController=new AbortController();const signal=editPhotoController.signal;
  try{const{data:{session}}=await db.auth.getSession();if(!session||signal.aborted||generation!==editorGeneration||epoch!==authEpoch)return;
    await Promise.all((post.images||[]).map(async(image,index)=>{
      try{const response=await fetch(`${config.supabaseUrl}/functions/v1/media-upload`,{method:'POST',headers:{Authorization:`Bearer ${session.access_token}`,apikey:config.supabasePublishableKey,'Content-Type':'application/json'},body:JSON.stringify({action:'read',post_id:post.id,image}),signal});if(!response.ok)throw new Error('Image access denied');const blob=await response.blob();if(!['image/jpeg','image/png','image/webp'].includes(blob.type))throw new Error('Unsupported image');if(signal.aborted||generation!==editorGeneration||epoch!==authEpoch||!canReadBoard(post.board,post.category))return;const url=URL.createObjectURL(blob);photoUrls.push(url);photoAssets[index].url=url;postEditor.updatePhoto(index,url);
      }catch{if(!signal.aborted&&generation===editorGeneration&&epoch===authEpoch)writeError('기존 사진 일부를 불러오지 못했어요. 다시 열어 확인해 주세요.');}
    }));
  }catch{if(!signal.aborted&&generation===editorGeneration)writeError('기존 사진을 불러오지 못했어요.');}
}
function openWrite(post=null){
  if(!displayedAccount()){openAuth();return;}
  if(ready&&!user){openAuth();toast('글을 쓰려면 먼저 로그인해 주세요.');return;}
  if(post&&!canManageContent(post)){toast('이 글을 수정할 권한이 없습니다.');return;}if(post&&!canReadBoard(post.board,post.category)){accessPanel(post.board,post.category);return;}
  if(ready&&user&&(post?!canWriteBoard(post.board,post.category):!writableBoards.size)){toast('글쓰기 권한이 없습니다.');return;}
  const form=document.querySelector('#write-form');form.reset();form.elements.board.innerHTML=Object.entries(boards).filter(([key])=>canWriteBoard(key)).map(([key,board])=>`<option value="${key}">${esc(board.name)}</option>`).join('');clearPhotos();form.dataset.postId=post?.id||'';form.elements.title.value=post?.title||'';form.elements.main_notice.checked=post?.is_notice===true;
  photoAssets=(post?.images||[]).map(originalUrl=>({originalUrl,url:boards[post.board].restricted?'./assets/photo-placeholder.svg':safeImage(originalUrl)}));
  try{postEditor.load(post?.body_doc,post?.body||'',photoAssets.map(asset=>asset.url));}catch{postEditor.load(null,post?.body||'',photoAssets.map(asset=>asset.url));}
  const current=location.hash.split('?')[0].split('/')[2];form.elements.board.value=post?.board||(canWriteBoard(current)?current:[...writableBoards][0]||'free');const category=new URLSearchParams(location.hash.split('?')[1]).get('category');form.elements.category.value=post?.board==='gallery'&&post.category?post.category:(Object.hasOwn(galleryCategories,category)?category:'meetup');form.elements.free_category.value=post?.board==='free'&&Object.hasOwn(freeCategories,post.category)?post.category:'chat';form.elements.staff_category.value=post?.board==='staff'&&Object.hasOwn(staffCategories,post.category)?post.category:Object.hasOwn(staffCategories,category)?category:'plot';updateGalleryCategory();document.querySelector('#write-title').textContent=post?'글 수정':'새 글 쓰기';document.querySelector('#write-submit').textContent=post?'수정하기':'등록하기';updateWriteAvailability();updateWriteAvailability();writeError('');document.querySelector('#write-dialog').showModal();
  if(post&&boards[post.board].restricted&&db)void loadEditPhotos(post);
}
main.addEventListener('click',event=>{if(event.target.closest('[data-auth]'))openAuth();if(event.target.closest('[data-signup]'))openAuth('signup');const write=event.target.closest('[data-write]');if(write)openWrite();const sortButton=event.target.closest('[data-sort]');if(sortButton){sort=sortButton.dataset.sort;page=1;render();}const pageButton=event.target.closest('[data-page]');if(pageButton&&!pageButton.disabled){page+=Number(pageButton.dataset.page);render();}});
document.querySelectorAll('[data-close-dialog]').forEach(button=>button.onclick=()=>button.closest('dialog').close());
document.querySelector('#write-dialog').addEventListener('close',()=>clearPhotos());
document.querySelector('#login-button').onclick=()=>user?signOut():openAuth();
document.querySelector('#signup-button').onclick=()=>openAuth('signup');
document.querySelector('#switch-auth').onclick=()=>openAuth(authMode==='login'?'signup':'login');
document.querySelector('#search-form').onsubmit=event=>{event.preventDefault();const value=document.querySelector('#search').value.trim();if(value){page=1;location.hash=`#/search?q=${encodeURIComponent(value)}`;}};
document.querySelector('#photos').onchange=event=>{addEditorPhotos([...event.target.files]);event.target.value='';};
document.querySelector('#auth-form').onsubmit=async event=>{
  event.preventDefault();if(!db)return;
  const form=event.currentTarget,values=new FormData(form),button=document.querySelector('#auth-submit'),signup=authMode==='signup';button.disabled=true;
  try{
    const fields={username:values.get('username').trim().toLowerCase(),password:values.get('password')};
    if(signup)Object.assign(fields,{password_confirmation:values.get('password_confirmation'),nickname:values.get('nickname').trim(),region:values.get('region').trim(),team:values.get('team'),yb_requested:values.has('yb_requested')});
    const result=await requestMembership(config,signup?'register':'login',fields);
    if(!signup){if(!result.session?.access_token||!result.session?.refresh_token)throw new Error('Missing session');const{error}=await db.auth.setSession(result.session);if(error)throw error;}
    form.reset();document.querySelector('#auth-dialog').close();toast(signup?'가입 신청이 접수됐어요. 관리자 승인 후 로그인할 수 있습니다.':'로그인했어요.');
  }catch(error){
    document.querySelector('#auth-error').textContent=error.code==='password_mismatch'?'비밀번호가 일치하지 않습니다.':error.code==='approval_pending'?'관리자 승인 대기 중입니다. 승인 완료 후 로그인해 주세요.':error.code==='membership_rejected'?'가입 신청이 승인되지 않았습니다. 운영자에게 문의해 주세요.':error.code==='membership_suspended'?'현재 이용이 정지된 계정입니다. 운영자에게 문의해 주세요.':error.code==='duplicate_id'?'이미 사용 중인 아이디입니다.':error.code==='rate_limited'?'잠시 후 다시 시도해 주세요.':signup?'가입 신청을 처리하지 못했어요. 입력한 내용을 확인하고 다시 시도해 주세요.':'로그인하지 못했어요. 아이디·비밀번호와 승인 여부를 확인해 주세요.';
  }finally{button.disabled=false;}
};
document.querySelector('#auth-form').addEventListener('input',()=>{const form=document.querySelector('#auth-form'),confirmation=form.elements.password_confirmation;confirmation.setCustomValidity(authMode==='signup'&&confirmation.value&&confirmation.value!==form.elements.password.value?'비밀번호가 일치하지 않습니다.':'');});
async function signOut(){const{error}=await db.auth.signOut();if(error){toast('로그아웃하지 못했어요.');return;}toast('로그아웃했어요.');}
function trustedMembership(data){return{...data,server_clock_offset:Number.isFinite(Date.parse(data.server_time))?Date.parse(data.server_time)-Date.now():0};}
function scheduleRestrictionRefresh(){clearTimeout(restrictionTimer);const member=displayedAccount()?.user_metadata;if(!member)return;const now=Date.now()+(Number(member.server_clock_offset)||0),next=[Date.parse(member.restriction_start),Date.parse(member.restriction_end)].filter(time=>Number.isFinite(time)&&time>now).sort((a,b)=>a-b)[0];if(!next)return;restrictionTimer=setTimeout(()=>{if(ready&&user)void refreshIdentity(user).catch(()=>toast('회원 상태를 확인하지 못했어요.'));else{updateAccount();void render();}},Math.min(2147483647,Math.max(250,next-now+250)));}
async function checkMembershipStatus(){if(!ready||!db||!user)return;const actor=user,epoch=authEpoch,{data,error}=await db.rpc('get_my_membership');if(error||!data||epoch!==authEpoch||user?.id!==actor.id)return;if(data.revision!==memberProfile?.revision||data.status!==memberProfile?.status||data.is_restricted!==memberProfile?.is_restricted)await refreshIdentity(actor);}
function updateAccount(){scheduleRestrictionRefresh();const account=displayedAccount(),actions=accountActions(account);document.querySelector('#member-strip').innerHTML=accountBar(account,{preview:!ready});const button=document.querySelector('#login-button');button.textContent=actions.loginLabel;button.disabled=ready&&!db;document.querySelector('#signup-button').hidden=!actions.signup;document.querySelector('#member-manage-button').hidden=!actions.manage;}
function selectedPostCategory(form){return form.elements.board.value==='gallery'?form.elements.category.value:form.elements.board.value==='free'?form.elements.free_category.value:form.elements.board.value==='staff'?form.elements.staff_category.value:null;}
function updateWriteAvailability(){const board=document.querySelector('#write-form').elements.board.value;document.querySelector('#write-submit').disabled=!db&&!(board==='recruit'&&canWriteBoard('recruit'));document.querySelector('#write-note').textContent=ready?'사진과 서식이 본문에 함께 저장됩니다.':board==='recruit'?'현재 등록한 글과 참석 댓글은 이 브라우저에서만 유지됩니다. 새로고침하면 초기화됩니다.':'실제 게시글 등록은 서비스 연결 후 사용할 수 있습니다.';}
function updateGalleryCategory(){updateWriteAvailability();const noticeField=document.querySelector('#main-notice-label'),canSelect=document.querySelector('#write-form').elements.board.value==='notice'&&canManageMembers(displayedAccount()?.user_metadata);noticeField.hidden=!canSelect;document.querySelector('#write-form').elements.main_notice.disabled=!canSelect;const form=document.querySelector('#write-form'),gallery=form.elements.board.value==='gallery',free=form.elements.board.value==='free',staff=form.elements.board.value==='staff';document.querySelector('#gallery-category-label').hidden=!gallery;form.elements.category.disabled=!gallery;document.querySelector('#free-category-label').hidden=!free;form.elements.free_category.disabled=!free;document.querySelector('#staff-category-label').hidden=!staff;form.elements.staff_category.disabled=!staff;for(const [field,categories] of [['category',galleryCategories],['staff_category',staffCategories]]){const input=form.elements[field],previous=input.value;input.innerHTML=Object.entries(categories).filter(([value])=>canWriteMenu(postMenu(field==='category'?'gallery':'staff',value))).map(([value,label])=>`<option value="${value}">${label}</option>`).join('');if([...input.options].some(option=>option.value===previous))input.value=previous;}}
document.querySelector('#write-form').elements.board.addEventListener('change',updateGalleryCategory);
async function uploadPhoto(file,board,category){return uploadCommunityPhoto(db,config,file,board,category);}
document.querySelector('#write-form').onsubmit=async event=>{
  event.preventDefault();if(!db&&(!displayedAccount()||event.currentTarget.elements.board.value!=='recruit'))return;if(db&&!user)return;
  const form=event.currentTarget,button=document.querySelector('#write-submit'),values=new FormData(form);if(!canWriteBoard(values.get('board'),selectedPostCategory(form))){writeError('이 게시판에 글쓰기 권한이 없습니다.');return;}button.disabled=true;button.textContent='저장 중…';
  try{const doc=postEditor.document(),indexes=imageIndexes(doc),body=documentText(doc);if(!body||body.length>10000)throw new Error('본문을 1~10,000자로 입력해 주세요.');if(indexes.length>5||indexes.some(index=>!photoAssets[index]))throw new Error('사진을 확인해 주세요.');
    const images=[];for(const index of indexes){const asset=photoAssets[index];if(!db&&asset.file)throw new Error('사진 업로드는 서비스 연결 후 사용할 수 있습니다.');asset.originalUrl=asset.originalUrl||await uploadPhoto(asset.file,values.get('board'),selectedPostCategory(form));images.push(asset.originalUrl);}
    const record={board:values.get('board'),category:values.get('board')==='gallery'?values.get('category'):values.get('board')==='free'?values.get('free_category'):values.get('board')==='staff'?values.get('staff_category'):null,title:values.get('title').trim(),body,body_doc:remapDocumentPhotos(doc,indexes),images};
    if(!db){const actor=displayedAccount(),id=form.dataset.postId||crypto.randomUUID(),previous=posts.find(item=>item.id===id);if(previous&&previous.author_id!==actor.id)throw new Error('작성자만 수정할 수 있습니다.');const recordPost={...previous,...record,id,author_id:actor.id,preview_member_id:actor.id,author:actor.user_metadata.nickname,...actor.user_metadata,created_at:previous?.created_at||new Date().toISOString(),likes:previous?.likes||0,commentCount:previous?.commentCount||0};posts=previous?posts.map(item=>item.id===id?recordPost:item):[recordPost,...posts];document.querySelector('#write-dialog').close();location.hash=`#/post/${id}`;await render();toast('현재 브라우저에 글을 등록했어요.');return;}
    const result=record.board==='notice'?await db.rpc('save_notice_post',{p_id:form.dataset.postId||null,p_title:record.title,p_body:record.body,p_doc:record.body_doc,p_images:record.images,p_main:form.elements.main_notice.checked}).then(result=>({...result,data:{id:result.data}})):form.dataset.postId?await db.from('posts').update(record).eq('id',form.dataset.postId).select('id').single():await db.from('posts').insert({...record,author_id:user.id}).select('id').single();if(result.error)throw result.error;await loadPosts();document.querySelector('#write-dialog').close();location.hash=`#/post/${result.data.id}`;await render();toast('글을 저장했어요.');
  }catch(error){writeError((error.message?.startsWith('사진')?error.message:'게시글을 저장하지 못했어요. 입력 내용과 게시판 권한을 확인해 주세요.')+' 입력 내용은 그대로 남아 있습니다.');}
  finally{button.disabled=false;button.textContent=form.dataset.postId?'수정하기':'등록하기';}
};
window.addEventListener('hashchange',()=>{page=1;sort=location.hash.startsWith('#/best')?'popular':'latest';window.scrollTo(0,0);render();});
document.querySelector('.skip-link').onclick=event=>{event.preventDefault();main.focus();main.scrollIntoView();};
document.querySelectorAll('[data-site-name]').forEach(el=>el.textContent=config.siteName||'야구보러갈래?');document.title=config.siteName||'야구보러갈래?';
document.querySelector('#team-options').innerHTML=teamChoices();
updateAccount();
if(!ready)await render();
let identityTask=null,identityTaskKey=null;
async function refreshIdentity(nextUser){
  const key=nextUser?.id||'guest';if(identityTask&&identityTaskKey===key)return identityTask;
  identityTaskKey=key;const task=performIdentityRefresh(nextUser);identityTask=task;
  try{return await task;}finally{if(identityTask===task){identityTask=null;identityTaskKey=null;}}
}
async function performIdentityRefresh(nextUser){
  const changed=user?.id!==nextUser?.id;if(changed){user=null;memberProfile=null;}const epoch=++authEpoch;accessLoading=true;posts=[];menuPermissions={};allowedBoards=new Set();writableBoards=new Set();clearPrivatePhotos();
  if(changed){document.querySelector('#write-dialog').close();document.querySelector('#write-form').reset();}
  updateAccount();await render();
  if(nextUser){
    const{data,error}=await db.rpc('get_my_membership');if(epoch!==authEpoch)return;
    if(error||!data||!['approved','suspended'].includes(data.status)){
      await db.auth.signOut();toast(error?'회원 정보를 확인하지 못했어요. 잠시 후 다시 로그인해 주세요.':'관리자 승인 대기 중입니다. 승인 완료 후 로그인해 주세요.');return;
    }
    user=nextUser;memberProfile=trustedMembership(data);updateAccount();await render();if(restrictionActive(memberProfile)){accessLoading=false;return;}
  }
  try{const{data,error}=await db.rpc('get_menu_permissions');if(epoch!==authEpoch)return;if(error||!data)throw error||new Error('Missing permissions');menuPermissions=data;allowedBoards=new Set(Object.keys(boards).filter(key=>canReadBoard(key)));writableBoards=new Set(Object.keys(boards).filter(key=>canWriteBoard(key)));}catch{if(epoch!==authEpoch)return;toast('추가 게시판 권한을 확인하지 못했어요. 잠시 뒤 다시 로그인해 주세요.');}
  if(epoch!==authEpoch)return;accessLoading=false;await loadPosts(epoch);if(epoch===authEpoch)await render();
}
if(ready){try{const{createClient}=await import('https://esm.sh/@supabase/supabase-js@2.57.4');db=createClient(config.supabaseUrl,config.supabasePublishableKey);document.querySelector('#auth-submit').disabled=false;const{data,error}=await db.auth.getSession();if(error)throw error;db.auth.onAuthStateChange((event,session)=>{if(event==='INITIAL_SESSION')return;if(session?.user?.id===user?.id&&memberProfile){if(event==='TOKEN_REFRESHED')return;if(event==='SIGNED_IN'){queueMicrotask(()=>checkMembershipStatus().catch(()=>{}));return;}}queueMicrotask(()=>refreshIdentity(session?.user||null).catch(()=>toast('게시글을 다시 불러오지 못했어요.')));});await refreshIdentity(data.session?.user||null);}catch{main.innerHTML='<div class="error-panel"><strong>커뮤니티에 연결하지 못했어요.</strong><p>저장 서비스 연결을 확인한 뒤 새로고침해 주세요.</p></div>';}}


if(ready){setInterval(()=>{if(document.visibilityState==='visible')void checkMembershipStatus().catch(()=>{});},60000);document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')void checkMembershipStatus().catch(()=>{});});}

// Optional structured browsing support in browsers implementing WebMCP.
const modelContext = document.modelContext;
if (modelContext?.registerTool) {
  const lifecycle = new AbortController();
  const tools = [
    {
      name: 'search_community_posts',
      title: '게시글 검색',
      description: 'Search the public posts available in this community and show matching posts in the page. Does not save or upload anything.',
      inputSchema: {type:'object',properties:{query:{type:'string',minLength:1,maxLength:100}},required:['query'],additionalProperties:false},
      annotations: {readOnlyHint:false,untrustedContentHint:true},
      async execute(input) {
        if(!input || typeof input.query!=='string' || !input.query.trim() || input.query.length>100 || Object.keys(input).some(key=>key!=='query')) throw new Error('Enter a search query of 1–100 characters.');
        const query=input.query.trim();
        document.querySelector('#search').value=query;
        location.hash=`#/search?q=${encodeURIComponent(query)}`;
        page=1;
        await render();
        return {mode:ready?'connected':'preview',posts:visiblePosts().filter(p=>(p.title+' '+p.body).toLowerCase().includes(query.toLowerCase())).map(p=>({id:p.id,title:p.title,board:p.board}))};
      }
    },
    {
      name: 'open_community_board',
      title: '게시판 열기',
      description: 'Navigate to a board using the permissions of the signed-in member. Does not publish or modify posts.',
      inputSchema: {type:'object',properties:{board:{type:'string',enum:Object.keys(boards)}},required:['board'],additionalProperties:false},
      annotations: {readOnlyHint:false,untrustedContentHint:true},
      async execute(input) {
        if(!input || !Object.hasOwn(boards,input.board) || Object.keys(input).some(key=>key!=='board')) throw new Error('Choose an existing board.');
        location.hash=`#/board/${input.board}`;
        page=1;sort='latest';
        await render();
        return {board:input.board,title:boards[input.board].name,access:canReadBoard(input.board)?'allowed':'restricted',mode:ready?'connected':'preview'};
      }
    }
  ];
  for(const tool of tools) {
    try { await modelContext.registerTool(tool,{signal:lifecycle.signal}); }
    catch { /* Browsing remains available when this optional API is unavailable. */ }
  }
  window.addEventListener('pagehide',()=>lifecycle.abort(),{once:true});
}
