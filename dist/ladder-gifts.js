export const ladderGifts=Object.freeze([
  {name:'카카오톡',action:'선물하기',image:'gift-kakao.png',url:'https://gift.kakao.com/home'},
  {name:'스타벅스',action:'바로가기',image:'gift-starbucks.png',url:'https://gift.kakao.com/product/11062288'},
  {name:'메가커피',action:'바로가기',image:'gift-mgc.png',url:'https://gift.kakao.com/product/11561213'},
  {name:'컴포즈 커피',action:'바로가기',image:'gift-compose.png',url:'https://gift.kakao.com/product/11983723'}
]);
export function ladderGiftLinks(){
  return `<section class="ladder-gift-links" aria-label="커피 선물하기" hidden>${ladderGifts.map(gift=>`<a href="${gift.url}" target="_blank" rel="noopener noreferrer" aria-label="${gift.name} ${gift.action} (새 창)"><img src="./assets/${gift.image}" alt="" width="80" height="80" loading="lazy" decoding="async"><span>${gift.name}<br>${gift.action}</span></a>`).join('')}</section>`;
}
