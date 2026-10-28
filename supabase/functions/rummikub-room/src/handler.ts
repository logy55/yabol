import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {createRoom,actRoom,settleRoom,roomView,roomListing} from './room-core.js';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
Deno.serve(async request=>{
 const origin=request.headers.get('Origin')||'',allowed=(Deno.env.get('ALLOWED_ORIGINS')||'https://yabol.co.kr,https://www.yabol.co.kr').split(',').map(s=>s.trim());
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
 const respond=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(!allowed.includes(origin))return respond({error:'Origin denied'},403);
 Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'});
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return respond({error:'Invalid method'},405);
 try{
  const authorization=request.headers.get('Authorization')||'';if(!authorization.startsWith('Bearer '))return respond({error:'Approved member required'},401);
  const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const client=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}}),auth=await client.auth.getUser();
  if(auth.error||!auth.data.user)return respond({error:'Approved member required'},401);
  const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}}),user=auth.data.user.id;
  const actorResult=await service.rpc('rummikub_actor',{p_user:user});if(actorResult.error||!actorResult.data)return respond({error:'Approved member required'},403);const actor=actorResult.data;
  const text=await request.text();if(text.length>30000)return respond({error:'Invalid request'},400);let body;try{body=JSON.parse(text);}catch{return respond({error:'Invalid request'},400);}
  const actions=['list','leaderboard','create','join','get','ready','settings','draft','commit','draw','leave','kick'];if(!actions.includes(body?.action))return respond({error:'Invalid action'},400);
  if(body.action==='leaderboard'){const result=await service.rpc('rummikub_leaderboard',{p_user:user});if(result.error)throw Error('Service unavailable');return respond({leaderboard:result.data});}
  if(body.action==='list'){const result=await service.rpc('rummikub_list',{p_user:user});if(result.error)throw Error('Service unavailable');return respond({rooms:result.data.map(roomListing)});}
  if(body.action==='create'){
   for(let retry=0;retry<3;retry++){const room=createRoom(actor,body),result=await service.rpc('rummikub_create',{p_user:user,p_state:room});if(!result.error)return respond({room:roomView(room,user)});if(result.error.code==='23505')continue;if(result.error.message.includes('limit'))return respond({error:'Room limit exceeded'},429);throw Error('Service unavailable');}
   return respond({error:'Service unavailable'},503);
  }
  if(body.action==='join'?!/^[a-f0-9]{6}$/i.test(body.code||''):!uuid.test(body.roomId||''))return respond({error:'Invalid room'},400);
  for(let retry=0;retry<4;retry++){
   const read=await service.rpc('rummikub_read',{p_user:user,p_room:body.action==='join'?null:body.roomId,p_code:body.action==='join'?body.code:null});
   if(read.error||!read.data)return respond({error:'Room not found'},404);
   const before=JSON.stringify(read.data.state),now=Date.now(),base=read.data.state;settleRoom(base,now);let room=structuredClone(base),failure=null;
   try{actRoom(room,actor,body.action,body,now);}catch(error){failure=error;room=base;}
   if(JSON.stringify(room)!==before){
    const save=await service.rpc('rummikub_store',{p_user:user,p_room:read.data.id,p_version:read.data.version,p_state:room});if(save.error)throw Error('Service unavailable');if(!save.data)continue;
   }
   let view;try{view=roomView(room,user,now);}catch{}
   if(failure)return respond({error:failure.message,room:view},409);
   return respond(body.action==='leave'?{left:true}:{room:view});
  }
  return respond({error:'경기 상태가 바뀌었습니다. 다시 시도해 주세요.'},409);
 }catch(error){return respond({error:/^[A-Za-z ]+$/.test(error?.message||'')?error.message:'Service unavailable'},503);}
});
