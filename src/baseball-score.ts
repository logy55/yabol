import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {validateBaseballInputs,verifyBaseballChunk} from './baseball-verify.js';
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
   const name=input.physicsVersion===3?'begin_baseball_run_v3':input.physicsVersion===2?'begin_baseball_run_v2':'begin_baseball_run';
   const{data,error}=await admin.rpc(name,{p_user:actor});
   if(error)return json({code:error.message.includes('Too many')?'rate_limited':'member_required'},error.message.includes('Too many')?429:403);
   return json({run:data});
  }
  if(input?.action==='recover'){
   const{data,error}=await admin.rpc('pending_baseball_verifications',{p_user:actor});
   return error?json({code:'member_required'},403):json({runs:data});
  }
  if(input?.action!=='finish'||typeof input.runId!=='string'||!uuid.test(input.runId))return json({code:'invalid_request'},400);
  const{data:run,error:runError}=await admin.rpc('baseball_run_for_validation',{p_user:actor,p_run:input.runId});
  if(runError||!run)return json({code:'game_unavailable'},403);
  if(run.finished_at)return json({result:{score:run.score,maxLevel:run.max_level,drops:run.drops,merges:run.merges}});
  const frames=run.verification_target??input.frames,inputs=run.verification_inputs??input.inputs;
  let chunk;try{validateBaseballInputs(Number(run.seed),inputs,frames);chunk=verifyBaseballChunk(Number(run.seed),inputs,frames,Number(run.physics_version)||1,run.verification_state??null);}catch(error){console.warn('baseball verification rejected',String(error instanceof Error?error.message:'invalid'));return json({code:'invalid_run'},400);}
  if(chunk.done){
   const result=chunk.result;
   const{data,error}=await admin.rpc('complete_baseball_verified_run',{p_user:actor,p_run:run.id,p_revision:run.verification_revision||0,p_score:result.score,p_level:result.maxLevel,p_frames:result.frames,p_drops:result.drops,p_merges:result.merges});
   if(error){console.warn('baseball result rejected',error.code,error.message);return json({code:'result_rejected'},400);}
   return json(data);
  }
  const{data,error}=await admin.rpc('save_baseball_verification',{p_user:actor,p_run:run.id,p_revision:run.verification_revision||0,p_inputs:run.verification_inputs?null:inputs,p_frames:frames,p_cursor:chunk.frame,p_state:chunk.state});
  if(error){console.warn('baseball checkpoint rejected',error.code,error.message);return json({code:'verification_unavailable'},503);}
  if(data.finished){const{data:finished}=await admin.rpc('baseball_run_for_validation',{p_user:actor,p_run:run.id});return json({result:{score:finished.score,maxLevel:finished.max_level,drops:finished.drops,merges:finished.merges}});}
  return json({pending:true,verifiedFrames:data.cursor,totalFrames:data.total},202);
 }catch{return json({code:'unavailable'},503);}
});
