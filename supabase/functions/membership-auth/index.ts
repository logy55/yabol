import {createClient} from 'npm:@supabase/supabase-js@2.57.4';

const getEnv=(name:string)=>{const value=Deno.env.get(name);if(!value)throw new Error('Missing server configuration');return value;};
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(n=>n.toString(16).padStart(2,'0')).join('');
const teams=new Set(['kia','samsung','lg','doosan','kt','ssg','lotte','hanwha','nc','kiwoom']);

Deno.serve(async(request:Request)=>{
  const origin=request.headers.get('Origin')||'';
  let headers:Record<string,string>={'Content-Type':'application/json','Vary':'Origin','Cache-Control':'no-store'};
  const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers});
  try{
    if(!getEnv('ALLOWED_ORIGINS').split(',').map(s=>s.trim()).includes(origin))return json({code:'origin_denied'},403);
    headers={...headers,'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'apikey, content-type, authorization, x-client-info'};
    if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
    if(request.method!=='POST')return json({code:'method_denied'},405);
    if(Number(request.headers.get('Content-Length')||0)>4096)return json({code:'invalid_request'},400);
    const body=await request.text();if(body.length>4096)return json({code:'invalid_request'},400);
    const input=JSON.parse(body);
    if(!input||!['register','login'].includes(input.action)||typeof input.username!=='string'||typeof input.password!=='string')return json({code:'invalid_request'},400);
    const username=input.username.trim().toLowerCase(),password=input.password;
    if(!/^[a-z0-9_]{3,24}$/.test(username)||password.length<8||new TextEncoder().encode(password).length>72)return json({code:'invalid_request'},400);
    if(input.action==='register'&&(typeof input.password_confirmation!=='string'||input.password_confirmation!==password))return json({code:'password_mismatch'},400);
    if(input.action==='register'&&typeof input.yb_requested!=='boolean')return json({code:'invalid_request'},400);
    const url=getEnv('SUPABASE_URL');
    const admin=createClient(url,getEnv('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
    const limit=async(key:string,max:number,seconds:number)=>{
      const{data,error}=await admin.rpc('membership_rate_limit',{p_key:key,p_limit:max,p_seconds:seconds});
      return !error&&data===true;
    };
    const remote=request.headers.get('x-forwarded-for')?.split(',')[0].trim()||'unknown';
    if(!await limit(`${input.action}:${await hash(remote)}`,input.action==='register'?10:30,3600))return json({code:'rate_limited'},429);
    if(!await limit(`login-id:${await hash(username)}`,15,300))return json({code:'rate_limited'},429);
    // This is an internal Auth identifier, never a member email or a delivery address.
    const alias=`${await hash(username)}@members.invalid`;
    if(input.action==='register'){
      if(!await limit('register-global',100,86400))return json({code:'rate_limited'},429);
      const nickname=typeof input.nickname==='string'?input.nickname.trim():'',region=typeof input.region==='string'?input.region.trim():'';
      if(nickname.length<2||nickname.length>20||region.length<1||region.length>20||!teams.has(input.team))return json({code:'invalid_request'},400);
      const{error}=await admin.auth.admin.createUser({email:alias,password,email_confirm:true,user_metadata:{username,nickname,region,team:input.team,yb_requested:input.yb_requested}});
      if(error)return json({code:error.code==='email_exists'||error.code==='user_already_exists'?'duplicate_id':'registration_failed'},409);
      return json({status:'pending'},201);
    }
    const auth=createClient(url,getEnv('SUPABASE_ANON_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
    const{data,error}=await auth.auth.signInWithPassword({email:alias,password});
    if(error||!data.user||!data.session)return json({code:'invalid_credentials'},401);
    const{data:status,error:approvalError}=await admin.rpc('get_member_status',{p_user:data.user.id});
    // Restricted members receive a session to see their release date; DB policies still deny board access.
    if(approvalError||!['approved','suspended'].includes(status)){
      await auth.auth.signOut();
      const code=approvalError?'unavailable':status==='rejected'?'membership_rejected':status==='suspended'?'membership_suspended':'approval_pending';
      return json({code},approvalError?503:403);
    }
    return json({session:{access_token:data.session.access_token,refresh_token:data.session.refresh_token}});
  }catch{return json({code:'unavailable'},503);}
});
