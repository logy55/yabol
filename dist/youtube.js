const videoPattern=/^[A-Za-z0-9_-]{11}$/;
export const validYoutubeId=value=>typeof value==='string'&&videoPattern.test(value);

// Accept only video URLs from YouTube; embed hosts/HTML are always generated here.
export function youtubeVideoId(value){
  if(typeof value!=='string'||value.length>2048)return null;
  let input=value.trim();
  if(/^(?:(?:www|m|music)\.)?youtube\.com\//i.test(input)||/^(?:www\.)?youtu\.be\//i.test(input))input='https://'+input;
  try{
    const url=new URL(input);
    if(!['https:','http:'].includes(url.protocol)||url.username||url.password||url.port)return null;
    const host=url.hostname,path=url.pathname.replace(/\/$/, '');let id=null;
    if(['youtu.be','www.youtu.be'].includes(host))id=path.slice(1);
    else if(['youtube.com','www.youtube.com','m.youtube.com','music.youtube.com'].includes(host)){
      if(path==='/watch')id=url.searchParams.get('v');
      else id=path.match(/^\/(?:embed|shorts|live)\/([A-Za-z0-9_-]{11})$/)?.[1];
    }else if(['youtube-nocookie.com','www.youtube-nocookie.com'].includes(host))id=path.match(/^\/embed\/([A-Za-z0-9_-]{11})$/)?.[1];
    return validYoutubeId(id)?id:null;
  }catch{return null;}
}
export const youtubeWatchUrl=id=>validYoutubeId(id)?`https://www.youtube.com/watch?v=${id}`:'';
export const youtubeEmbedUrl=id=>validYoutubeId(id)?`https://www.youtube-nocookie.com/embed/${id}?rel=0&playsinline=1`:'';
export function youtubeHTML(id){
  if(!validYoutubeId(id))throw new Error('올바른 유튜브 영상 주소를 입력해 주세요.');
  return `<figure class="youtube-video" data-youtube-id="${id}"><div class="youtube-player"><iframe src="${youtubeEmbedUrl(id)}" title="유튜브 동영상" width="640" height="360" loading="lazy" referrerpolicy="strict-origin-when-cross-origin" allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></div><figcaption><a href="${youtubeWatchUrl(id)}" target="_blank" rel="noopener noreferrer">YouTube에서 보기</a></figcaption></figure>`;
}
