export async function uploadCommunityPhoto(db,config,file,board,category=null){
  const{data:signature,error}=await db.functions.invoke('media-upload',{body:{action:'sign',board,category}});
  if(error||!signature?.signature)throw new Error('사진 업로드 권한을 확인하지 못했어요. 로그인 상태와 게시판 권한을 확인해 주세요.');
  const form=new FormData();form.set('file',file);
  for(const key of ['timestamp','signature','api_key','public_id','upload_preset','type'])if(signature[key]!=null)form.set(key,String(signature[key]));
  let response;
  try{response=await fetch(`https://api.cloudinary.com/v1_1/${encodeURIComponent(config.cloudinaryCloudName)}/image/upload`,{method:'POST',body:form});}catch{throw new Error('사진 저장소에 연결하지 못했어요. 네트워크 연결을 확인해 주세요.');}
  const uploaded=await response.json();
  if(!response.ok){
    const message=String(uploaded.error?.message||'');
    // Return only known diagnostics; never display signatures, IDs or credentials.
    const detail=/signature/i.test(message)?'사진 저장소 인증 설정을 확인해야 합니다.':/preset/i.test(message)?'사진 업로드 설정을 확인해야 합니다.':/format/i.test(message)?'JPG·PNG·WEBP 사진을 선택해 주세요.':/size|large/i.test(message)?'사진 용량이 너무 큽니다.':/cloud|api.key/i.test(message)?'사진 저장소 연결 설정을 확인해야 합니다.':'잠시 후 다시 시도해 주세요.';
    throw new Error(`사진 저장에 실패했어요. ${detail}`);
  }
  const{data:asset,error:verifyError}=await db.functions.invoke('media-upload',{body:{action:'verify',upload:uploaded}});
  if(verifyError||!asset?.url)throw new Error('사진은 업로드됐지만 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
  return asset.url;
}
