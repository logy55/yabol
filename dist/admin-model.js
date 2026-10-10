export const adminBoards=Object.freeze({free:'게시판 · 자유게시판',humor:'게시판 · 유머게시판',recruit:'게시판 · 모집게시판',gallery_flash:'사진첩 · 벙개 사진',gallery_attendance:'사진첩 · 직관 사진',gallery_meetup:'사진첩 · 정모 사진',notice:'공지사항',staff_plot:'운영진 · 작당모의',staff_minutes:'운영진 · 회의록',yb_roster:'YB Holics · 선수단',yb_calendar:'YB Holics · 경기 일정',yb_holics:'YB Holics · 홀릭스 게시판'});
export const publicMenus=Object.freeze([]);
export const boardMenus=Object.freeze({free:['free'],humor:['humor'],recruit:['recruit'],gallery:['gallery_flash','gallery_attendance','gallery_meetup'],notice:['notice'],staff:['staff_plot','staff_minutes'],yb:['yb_holics']});
export function postMenu(board,category){if(board==='gallery')return category==='flash'?'gallery_flash':category==='attendance'?'gallery_attendance':category==='meme'?'gallery_flash':'gallery_meetup';if(board==='staff')return category==='minutes'?'staff_minutes':'staff_plot';return board==='yb'?'yb_holics':board;}
export const statusLabels=Object.freeze({pending:'가입 대기',approved:'승인',rejected:'가입 거절',suspended:'이용 제한'});
export const roleLabels=Object.freeze({member:'일반회원',staff:'운영진',vice_staff:'부운영진'});
export const ybRoleLabels=Object.freeze({member:'일반 멤버',director:'감독',manager:'매니저'});
export const accessLabels=Object.freeze({deny:'접근 불가',read:'읽기만',write:'읽기·쓰기'});

// Call with the server membership profile, never editable Auth metadata.
export function canManageMembers(member){
  return member?.status==='approved'&&!restrictionActive(member)&&(member.is_admin===true||['staff','vice_staff'].includes(member.staff_role));
}
export function canManageRoster(member){
  return canManageMembers(member)||(member?.status==='approved'&&!restrictionActive(member)&&member.is_yb_member===true&&['director','manager'].includes(member.yb_role));
}

export function effectivePermission(member,board,permissions=member?.permissions||{}){
  if(!Object.hasOwn(adminBoards,board)){const menus=boardMenus[board];if(!menus)return 'deny';const access=menus.map(menu=>effectivePermission(member,menu,permissions));return access.includes('write')?'write':access.includes('read')?'read':'deny';}
  if(!member)return publicMenus.includes(board)?'read':'deny';
  if(member.status!=='approved'||restrictionActive(member))return 'deny';
  if(member.is_admin===true)return 'write';
  const override=permissions[board];
  if(board==='yb_roster'||board==='yb_calendar')return override==='deny'?'deny':override==='read'?'read':canManageRoster(member)?'write':'read';
  if(board==='recruit')return override==='deny'?'deny':override==='read'?'read':canManageMembers(member)?'write':'read';
  if(Object.hasOwn(accessLabels,override))return override;
  if(board==='free'||board==='humor'||board.startsWith('gallery_'))return 'write';
  const staff=['staff','vice_staff'].includes(member.staff_role);
  if(board==='notice')return staff?'write':'read';
  if(board.startsWith('staff_'))return staff?'write':'deny';
  return staff||member.is_yb_member===true?'write':'deny';
}
export function fullPermissions(member){return Object.fromEntries(Object.keys(adminBoards).map(board=>[board,member.permissions?.[board]||'default']));}
export function summarizeMemberChanges(before,after){
  const changes=[];
  for(const [key,label] of [['nickname','이름'],['region','지역']])if(before[key]!==after[key])changes.push(`${label}: ${before[key]||'—'} → ${after[key]||'—'}`);
  if(before.team!==after.team)changes.push(`응원 구단: ${getTeam(before.team)?.name||'미선택'} → ${getTeam(after.team)?.name||'미선택'}`);
  for(const [key,label,values] of [['status','승인 상태',statusLabels],['staff_role','등급',roleLabels]])if(before[key]!==after[key])changes.push(`${label}: ${values[before[key]]} → ${values[after[key]]}`);
  for(const [key,label] of [['is_yb_member','YB 소속'],['is_admin','어드민 권한']])if(before[key]!==after[key])changes.push(`${label} ${after[key]?'부여':'해제'}`);
  if((before.yb_role||'member')!==(after.yb_role||'member'))changes.push(`YB 직책: ${ybRoleLabels[before.yb_role||'member']} → ${ybRoleLabels[after.yb_role||'member']}`);
  if(before.restriction_start!==after.restriction_start||before.restriction_end!==after.restriction_end)changes.push(after.restriction_end?`이용 제한 기간 설정 · 해제 ${new Date(after.restriction_end).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'})}`:'이용 제한 해제');
  for(const [board,label] of Object.entries(adminBoards))if((before.permissions?.[board]||'default')!==(after.permissions?.[board]||'default'))changes.push(`${label}: ${accessLabels[after.permissions?.[board]]||'기본값'}`);
  return changes.join(' · ')||'설정 확인';
}
import {restrictionActive} from './restrictions.js?v=20261010-member-fixes';

import {getTeam} from './teams.js?v=20261010-member-fixes';
