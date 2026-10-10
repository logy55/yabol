import {memberName, getTeam} from './teams.js?v=20261010-member-fixes';
import {canManageMembers} from './admin-model.js?v=20261010-recruit-rights';
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const nickname = user => typeof user?.user_metadata?.nickname === 'string' ? user.user_metadata.nickname.trim() || '회원' : '회원';

export function accountActions(user) {
  return {signup:!user,manage:Boolean(user)&&canManageMembers(user.user_metadata||{}),loginLabel:user?'로그아웃':'로그인'};
}

export function accountBar(user, {preview=false}={}) {
  if (!user) return '<span class="member-guest">로그인 후 내 정보를 확인할 수 있어요.</span>';
  const profile = user.user_metadata || {};
  return `<span class="member-greeting">${memberName(nickname(user), profile.team, profile.region, profile.staff_role, profile.is_yb_member)}</span><a class="member-link" href="#/account">내 정보</a>`;
}

export function accountView(user, {preview=false}={}) {
  if (!user) return '<section class="access-panel"><h1>내 정보</h1><p>로그인 후 내 정보를 확인할 수 있어요.</p><div class="access-actions"><button class="primary" data-auth>로그인</button></div></section>';
  const joined = user.created_at ? new Date(user.created_at) : null;
  const joinedText = joined && !Number.isNaN(joined.getTime()) ? joined.toLocaleDateString('ko-KR', {year:'numeric',month:'long',day:'numeric'}) : '—';
  const profile = user.user_metadata || {};
  return `<section class="account-page"><div class="board-heading"><div><h1>내 정보</h1><p>내 회원 정보를 확인하세요.</p></div>${preview?'':'<button type="button" class="secondary" id="account-edit">정보 수정</button>'}</div><div class="account-card"><dl class="account-details"><div><dt>아이디</dt><dd>${escapeHtml(profile.username || '—')}</dd></div><div><dt>이름</dt><dd class="member-identity">${memberName(nickname(user), profile.team, profile.region, profile.staff_role, profile.is_yb_member)}</dd></div><div><dt>응원 구단</dt><dd>${escapeHtml(getTeam(profile.team)?.name || '—')}</dd></div><div><dt>지역</dt><dd>${escapeHtml(profile.region || '—')}</dd></div><div><dt>가입일</dt><dd>${escapeHtml(joinedText)}</dd></div></dl></div><div class="account-content-actions"><a class="secondary" href="#/trash">삭제한 글·댓글</a></div></section>`;
}

export function validateProfileInfo(nickname,region){
  const values={nickname:String(nickname??'').trim(),region:String(region??'').trim()};
  if([...values.nickname].length<2||[...values.nickname].length>20||/[\u0000-\u001f\u007f]/.test(values.nickname))throw new Error('Invalid profile nickname');
  if([...values.region].length<1||[...values.region].length>20||/[\u0000-\u001f\u007f]/.test(values.region))throw new Error('Invalid profile region');
  return values;
}
export function profileErrorText(error){
  const message=error?.message||'';
  if(message.includes('Invalid profile nickname'))return '이름은 2~20자로 입력해 주세요.';
  if(message.includes('Invalid profile region'))return '지역은 1~20자로 입력해 주세요.';
  if(message.includes('reload required'))return '회원 정보가 변경되었습니다. 새로고침 후 다시 확인해 주세요.';
  if(message.includes('Approved member required'))return '현재 회원 상태에서는 정보를 수정할 수 없습니다.';
  return '';
}
export function renderAccount(main,{user,db,preview=false,isCurrent,onSaved,notify}){
  let current=user,busy=false;
  function draw(){
    main.innerHTML=accountView(current,{preview});
    const root=main.querySelector('.account-page');
    if(!root||preview)return;
    const alive=()=>isCurrent()&&main.contains(root),button=root.querySelector('#account-edit');
    button.onclick=()=>{
      if(busy||root.querySelector('#account-profile-form'))return;
      button.hidden=true;
      const profile=current.user_metadata||{},card=root.querySelector('.account-card');
      card.insertAdjacentHTML('afterend',`<form id="account-profile-form" class="account-profile-form"><h2>회원 정보 수정</h2><fieldset><div class="account-profile-fields"><label>이름<input name="nickname" value="${escapeHtml(profile.nickname)}" minlength="2" maxlength="20" autocomplete="name" required></label><label>지역<input name="region" value="${escapeHtml(profile.region)}" maxlength="20" required></label></div><p class="form-error" role="alert" id="account-profile-error"></p><div class="form-actions"><button type="button" class="secondary" id="account-profile-cancel">취소</button><button type="submit" class="primary">저장</button></div></fieldset></form>`);
      const form=root.querySelector('#account-profile-form'),fieldset=form.querySelector('fieldset'),errorElement=form.querySelector('#account-profile-error');
      form.elements.nickname.focus();
      form.querySelector('#account-profile-cancel').onclick=()=>{if(busy)return;form.remove();button.hidden=false;button.focus();};
      form.onsubmit=async event=>{
        event.preventDefault();if(busy)return;errorElement.textContent='';
        let values;try{values=validateProfileInfo(form.elements.nickname.value,form.elements.region.value);}catch(error){errorElement.textContent=profileErrorText(error);return;}
        busy=true;fieldset.disabled=true;
        try{
          const {data,error}=await db.rpc('update_my_profile',{p_nickname:values.nickname,p_region:values.region,p_revision:profile.revision});
          if(error)throw error;if(!alive())return;
          current={...current,user_metadata:{...profile,...data}};
          await onSaved(data);if(!alive())return;
          draw();notify('이름과 지역을 저장했어요.');
        }catch(error){if(alive())errorElement.textContent=profileErrorText(error)||'저장하지 못했어요. 입력 내용을 확인하고 다시 시도해 주세요.';}
        finally{busy=false;if(alive())fieldset.disabled=false;}
      };
    };
  }
  draw();
}
