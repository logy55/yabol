const menus = {
  boards: [['자유게시판', '#/board/free'], ['유머게시판', '#/board/humor'], ['모집게시판', '#/board/recruit']],
  gallery: [['벙개 사진', '#/board/gallery?category=flash'], ['직관 사진', '#/board/gallery?category=attendance'], ['정모 사진', '#/board/gallery?category=meetup']],
  tools: [['사다리 게임', '#/tools/ladder'], ['정산 계산기', '#/tools/settlement'], ['매직넘버 계산기', '#/tools/magic-number']],
  staff: [['작당모의', '#/board/staff?category=plot'], ['회의록', '#/board/staff?category=minutes']],
  yb: [['선수단', '#/yb/roster'], ['경기 일정', '#/yb/calendar'], ['홀릭스 게시판', '#/board/yb']]
};
const header = document.querySelector('.site-header');
const popup = document.querySelector('#nav-dropdown');
let activeTrigger = null;

function positionMenu() {
  if (!activeTrigger) return;
  const button = activeTrigger.getBoundingClientRect();
  const bounds = header.getBoundingClientRect();
  popup.style.top = `${button.bottom - bounds.top + 4}px`;
  popup.style.left = `${Math.max(12, Math.min(button.left - bounds.left, window.innerWidth - popup.offsetWidth - 12))}px`;
}
export function closeMenu(returnFocus = false) {
  if (returnFocus) activeTrigger?.focus();
  activeTrigger?.setAttribute('aria-expanded', 'false');
  activeTrigger = null;
  popup.hidden = true;
}
function openMenu(trigger, focusFirst = false) {
  if (trigger === activeTrigger) { closeMenu(); return; }
  closeMenu();
  activeTrigger = trigger;
  popup.innerHTML = menus[trigger.dataset.dropdown].map(([label, href]) => `<a href="${href}">${label}</a>`).join('');
  popup.setAttribute('aria-label', `${trigger.textContent.trim()} 하위 메뉴`);
  popup.hidden = false;
  trigger.setAttribute('aria-expanded', 'true');
  positionMenu();
  if (focusFirst) popup.querySelector('a').focus();
}
document.querySelectorAll('[data-dropdown]').forEach(trigger => {
  trigger.addEventListener('click', () => openMenu(trigger));
  trigger.addEventListener('keydown', event => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      if (activeTrigger !== trigger) openMenu(trigger, true);
      else popup.querySelector('a').focus();
    }
  });
});
popup.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
popup.addEventListener('keydown', event => {
  const links = [...popup.querySelectorAll('a')];
  const index = links.indexOf(document.activeElement);
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    links[(index + (event.key === 'ArrowDown' ? 1 : -1) + links.length) % links.length].focus();
  }
});
document.addEventListener('click', event => {
  if (!popup.contains(event.target) && !event.target.closest('[data-dropdown]')) closeMenu();
});
document.addEventListener('keydown', event => { if (event.key === 'Escape' && activeTrigger) closeMenu(true); });
document.addEventListener('focusin', event => {
  if (activeTrigger && !popup.contains(event.target) && event.target !== activeTrigger) closeMenu();
});
document.querySelector('.main-nav').addEventListener('scroll', () => closeMenu(), {passive:true});
window.addEventListener('resize', positionMenu);
window.addEventListener('hashchange', () => closeMenu());
new ResizeObserver(() => {
  document.documentElement.style.setProperty('--header-height', `${header.offsetHeight}px`);
  positionMenu();
}).observe(header);
