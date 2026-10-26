import{createClient}from'npm:@supabase/supabase-js@2.57.4';
import{validate2048Result}from'./game2048-result.js';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
Deno.serve(async(request:Request)=>{
 const origin=request.headers.get('Origin')||'',headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
 const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 try{
  if(!(Deno.env.get('ALLOWED_ORIGINS')||'').split(',').map(s=>s.trim()).includes(origin))return json({code:'origin_denied'},403);
  Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});if(request.method!=='POST')return json({code:'method_denied'},405);
  const authorization=request.headers.get('Authorization')||'';if(!authorization.startsWith('Bearer '))return json({code:'login_required'},401);
  const auth=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}}),identity=await auth.auth.getUser();
  if(identity.error||!identity.data.user)return json({code:'login_required'},401);
  const text=await request.text();if(text.length>6000)return json({code:'invalid_request'},400);let input;try{input=JSON.parse(text);}catch{return json({code:'invalid_request'},400);}
  const actor=identity.data.user.id,admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  if(input?.action==='start'){const{data,error}=await admin.rpc('begin_game2048_run',{p_user:actor});return error?json({code:error.message.includes('Too many')?'rate_limited':'member_required'},error.message.includes('Too many')?429:403):json({run:data});}
  if(input?.action!=='save'||typeof input.runId!=='string'||!uuid.test(input.runId))return json({code:'invalid_request'},400);
  const{data:run,error:runError}=await admin.rpc('game2048_run_for_save',{p_user:actor,p_run:input.runId});if(runError||!run)return json({code:'game_unavailable'},403);
  if(run.finished_at)return json({result:{score:run.score,moves:run.moves,maxTile:run.max_tile,kind:'over'}});
  let result;try{result=validate2048Result(Number(run.seed),input);}catch{return json({code:'invalid_result'},400);}
  const{data,error}=await admin.rpc('complete_game2048_run',{p_user:actor,p_run:input.runId,p_score:result.score,p_moves:result.moves,p_tile:result.maxTile,p_kind:result.kind});
  return error?json({code:'result_rejected'},400):json({result:data});
 }catch{return json({code:'unavailable'},503);}
});
