import {memberName, getTeam} from './teams.js?v=20261010-community-final';
import {canManageMembers} from './admin-model.js?v=20261010-community-final';
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
  return `<section class="account-page"><div class="board-heading"><div><h1>내 정보</h1><p>내 회원 정보를 확인하세요.</p></div></div><div class="account-card"><dl class="account-details"><div><dt>아이디</dt><dd>${escapeHtml(profile.username || '—')}</dd></div><div><dt>닉네임</dt><dd class="member-identity">${memberName(nickname(user), profile.team, profile.region, profile.staff_role, profile.is_yb_member)}</dd></div><div><dt>응원 구단</dt><dd>${escapeHtml(getTeam(profile.team)?.name || '—')}</dd></div><div><dt>지역</dt><dd>${escapeHtml(profile.region || '—')}</dd></div><div><dt>가입일</dt><dd>${escapeHtml(joinedText)}</dd></div></dl></div></section>`;
}
