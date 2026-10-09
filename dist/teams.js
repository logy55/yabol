export const teams = Object.freeze([
  {id:'kia',name:'KIA 타이거즈',logo:'./assets/teams/kia-transparent.png'},
  {id:'samsung',name:'삼성 라이온즈',logo:'./assets/teams/samsung-transparent.png'},
  {id:'lg',name:'LG 트윈스',logo:'./assets/teams/lg-transparent.png'},
  {id:'doosan',name:'두산 베어스',logo:'./assets/teams/doosan-transparent.png'},
  {id:'kt',name:'KT 위즈',logo:'./assets/teams/kt-transparent.png'},
  {id:'ssg',name:'SSG 랜더스',logo:'./assets/teams/ssg-transparent.png'},
  {id:'lotte',name:'롯데 자이언츠',logo:'./assets/teams/lotte-transparent.png'},
  {id:'hanwha',name:'한화 이글스',logo:'./assets/teams/hanwha-transparent.png'},
  {id:'nc',name:'NC 다이노스',logo:'./assets/teams/nc.svg'},
  {id:'kiwoom',name:'키움 히어로즈',logo:'./assets/teams/kiwoom-transparent.png'}
]);

export const getTeam = id => teams.find(team => team.id === id);
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));

export function memberName(name, teamId, region, staffRole='member', isYbMember=false) {
  const team = getTeam(teamId);
  const area = typeof region === 'string' ? region.trim() : '';
  const staffTitle = staffRole==='staff'?'운영진':staffRole==='vice_staff'?'부운영진':null;
  const crown = staffTitle ? `<img class="staff-role-icon${staffRole==='vice_staff'?' staff-role-silver':''}" src="./assets/crown.png" alt="${staffTitle} 왕관" title="${staffTitle}" width="22" height="22">` : '';
  const yb = isYbMember===true ? '<img class="yb-member-icon" src="./assets/yb-hat.svg" alt="YB Holics 회원" title="YB Holics" width="22" height="22">' : '';
  return `${crown}${yb}${team ? `<span class="member-logo-crop" data-team="${team.id}"><img class="member-team-logo" src="${team.logo}" alt="${team.name} 로고" width="22" height="22"></span>` : ''}<span class="member-name-text">${escapeHtml(name || '회원')}${area ? ` <span class="member-region">· ${escapeHtml(area)}</span>` : ''}</span>`;
}

export function teamChoices() {
  return teams.map(team => `<label class="team-choice"><input type="radio" name="team" value="${team.id}" required><span>${team.name}</span></label>`).join('');
}
