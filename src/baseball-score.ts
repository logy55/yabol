import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {verifyBaseballRun} from './baseball-verify.js';
const env=(name:string)=>{const value=Deno.env.get(name);if(!value)throw Error('Configuration unavailable');return value;};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
Deno.serve(async(request:Request)=>{
 const origin=request.headers.get('Origin')||'';let headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
 const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 try{
  if(!env('ALLOWED_ORIGINS').split(',').map(s=>s.trim()).includes(origin))return json({code:'origin_denied'},403);
  headers={...headers,'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'};
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return json({code:'method_denied'},405);
  const authorization=request.headers.get('Authorization')||'';if(!authorization.startsWith('Bearer '))return json({code:'login_required'},401);
  const auth=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const{data:identity,error:authError}=await auth.auth.getUser();if(authError||!identity.user)return json({code:'login_required'},401);
  if(Number(request.headers.get('Content-Length')||0)>450000)return json({code:'invalid_request'},400);
  const text=await request.text();if(text.length>450000)return json({code:'invalid_request'},400);
  let input;try{input=JSON.parse(text);}catch{return json({code:'invalid_request'},400);}
  const admin=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}}),actor=identity.user.id;
  if(input?.action==='start'){
   const{data,error}=await admin.rpc('begin_baseball_run',{p_user:actor});
   if(error)return json({code:error.message.includes('Too many')?'rate_limited':'member_required'},error.message.includes('Too many')?429:403);
   return json({run:data});
  }
  if(input?.action!=='finish'||typeof input.runId!=='string'||!uuid.test(input.runId))return json({code:'invalid_request'},400);
  const{data:run,error:runError}=await admin.rpc('baseball_run_for_validation',{p_user:actor,p_run:input.runId});
  if(runError||!run)return json({code:'game_unavailable'},403);
  if(run.finished_at)return json({result:{score:run.score,maxLevel:run.max_level,drops:run.drops,merges:run.merges}});
  let result;try{result=verifyBaseballRun(Number(run.seed),input.inputs,input.frames);}catch{return json({code:'invalid_run'},400);}
  const{data,error}=await admin.rpc('complete_baseball_run',{p_user:actor,p_run:run.id,p_score:result.score,p_level:result.maxLevel,p_frames:result.frames,p_drops:result.drops,p_merges:result.merges});
  if(error)return json({code:'result_rejected'},400);
  return json({result:data});
 }catch{return json({code:'unavailable'},503);}
});
