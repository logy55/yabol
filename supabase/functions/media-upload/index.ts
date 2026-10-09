// Server-side only. Restricted assets use authenticated Cloudinary delivery.
import {createClient} from 'npm:@supabase/supabase-js@2.57.4';

const getEnv=(name:string)=>{const value=Deno.env.get(name);if(!value)throw new Error(`Missing ${name}`);return value;};
const allowedOrigins=()=>getEnv('ALLOWED_ORIGINS').split(',').map(s=>s.trim()).filter(Boolean);
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(n=>n.toString(16).padStart(2,'0')).join('');
const sign=async(params:Record<string,string|number>,secret:string)=>hash(Object.keys(params).sort().map(key=>`${key}=${params[key]}`).join('&')+secret);
const restricted=(board:string)=>['staff','yb'].includes(board);

Deno.serve(async(request:Request)=>{
  const origin=request.headers.get('Origin')||'';
  let headers:Record<string,string>={'Content-Type':'application/json','Vary':'Origin','Cache-Control':'no-store'};
  const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers});
  try{
    if(!allowedOrigins().includes(origin))return json({error:'Origin not allowed'},403);
    headers={...headers,'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
    if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
    if(request.method!=='POST')return json({error:'Method not allowed'},405);
    const authorization=request.headers.get('Authorization')||'';
    if(!authorization.startsWith('Bearer '))return json({error:'Sign in required'},401);
    const admin=createClient(getEnv('SUPABASE_URL'),getEnv('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:identity,error:identityError}=await admin.auth.getUser(authorization.slice(7));
    if(identityError||!identity.user?.email_confirmed_at)return json({error:'Verified member required'},401);
    const user=identity.user,input=await request.json();
    if(!input||typeof input!=='object')return json({error:'Invalid request'},400);
    const canAccess=async(board:string,write=false,category:string|null=null)=>{
      if(board==='yb_roster'){
        if(!write)return false;
        const {data,error}=await admin.rpc('member_can_write_menu',{p_user:user.id,p_menu:'yb_roster'});
        return !error&&data===true;
      }
      const {data,error}=await admin.rpc(write?'member_can_write_post_menu':'member_can_read_post_menu',{p_user:user.id,p_board:board,p_category:category});
      return !error&&data===true;
    };
    const cloud=getEnv('CLOUDINARY_CLOUD_NAME'),apiKey=getEnv('CLOUDINARY_API_KEY'),secret=getEnv('CLOUDINARY_API_SECRET');
    if(input.action==='sign'){
      const board=input.board;
      if(typeof board!=='string'||!await canAccess(board,true,typeof input.category==='string'?input.category:null))return json({error:'Board access denied'},403);
      const publicId=`community/${user.id}/${crypto.randomUUID()}`;
      const {error}=board==='yb_roster'
        ?await admin.rpc('reserve_roster_upload',{p_owner:user.id,p_public_id:publicId})
        :await admin.rpc('reserve_menu_upload',{p_owner:user.id,p_public_id:publicId,p_board:board,p_category:typeof input.category==='string'?input.category:null});
      if(error)return json({error:'Upload not permitted or limit reached'},429);
      const params={public_id:publicId,timestamp:Math.floor(Date.now()/1000),type:restricted(board)?'authenticated':'upload',upload_preset:getEnv(restricted(board)?'CLOUDINARY_PRIVATE_SIGNED_PRESET':'CLOUDINARY_SIGNED_PRESET')};
      return json({...params,api_key:apiKey,signature:await sign(params,secret)});
    }
    if(input.action==='verify'){
      const publicId=input.upload?.public_id;
      if(typeof publicId!=='string'||!publicId.startsWith(`community/${user.id}/`))return json({error:'Invalid asset'},400);
      const {data:ticket,error:ticketError}=await admin.from('upload_tickets').select('public_id,owner_id,board,category,delivery_type,secure_url,verified_at').eq('public_id',publicId).eq('owner_id',user.id).maybeSingle();
      if(ticketError||!ticket)return json({error:'Unknown upload'},400);
      if(!await canAccess(ticket.board,true,ticket.category))return json({error:'Board access denied'},403);
      if(ticket.verified_at)return json({url:ticket.secure_url});
      const metadataResponse=await fetch(`https://api.cloudinary.com/v1_1/${encodeURIComponent(cloud)}/resources/image/${ticket.delivery_type}/${encodeURIComponent(publicId)}`,{headers:{Authorization:`Basic ${btoa(`${apiKey}:${secret}`)}`}});
      if(!metadataResponse.ok)return json({error:'Asset not available'},502);
      const asset=await metadataResponse.json();
      if(asset.public_id!==publicId||asset.resource_type!=='image'||asset.type!==ticket.delivery_type||!['jpg','png','webp'].includes(asset.format)||!Number.isSafeInteger(asset.bytes)||asset.bytes>10*1024*1024||asset.bytes<1||!Number.isSafeInteger(asset.version))return json({error:'Unsupported image'},400);
      // Do not store signed delivery URLs: those would bypass membership checks.
      const path=publicId.split('/').map(encodeURIComponent).join('/');
      const url=`https://res.cloudinary.com/${encodeURIComponent(cloud)}/image/${ticket.delivery_type}/v${asset.version}/${path}.${asset.format}`;
      const {error:saveError}=await admin.from('upload_tickets').update({secure_url:url,format:asset.format,verified_at:new Date().toISOString()}).eq('public_id',publicId).eq('owner_id',user.id);
      if(saveError)throw new Error('Could not register image');
      return json({url});
    }
    if(input.action==='read'){
      if(typeof input.post_id!=='string'||typeof input.image!=='string')return json({error:'Invalid image request'},400);
      const {data:post,error:postError}=await admin.from('posts').select('board,category,images').eq('id',input.post_id).maybeSingle();
      if(postError||!post||!restricted(post.board)||!await canAccess(post.board,false,post.category)||!post.images.includes(input.image))return json({error:'Image access denied'},403);
      const {data:ticket,error:ticketError}=await admin.from('upload_tickets').select('public_id,format,board,delivery_type,verified_at').eq('secure_url',input.image).maybeSingle();
      if(ticketError||!ticket?.verified_at||ticket.board!==post.board||ticket.delivery_type!=='authenticated'||!['jpg','png','webp'].includes(ticket.format))return json({error:'Image access denied'},403);
      const timestamp=Math.floor(Date.now()/1000);
      const params={public_id:ticket.public_id,format:ticket.format,type:'authenticated',timestamp,expires_at:timestamp+60};
      const query=new URLSearchParams(Object.entries(params).map(([key,value])=>[key,String(value)]));
      query.set('api_key',apiKey);query.set('signature',await sign(params,secret));
      const response=await fetch(`https://api.cloudinary.com/v1_1/${encodeURIComponent(cloud)}/image/download?${query}`);
      if(!response.ok)return json({error:'Image unavailable'},502);
      const mime=ticket.format==='jpg'?'image/jpeg':`image/${ticket.format}`;
      const data=await response.arrayBuffer();
      if(data.byteLength>10*1024*1024)return json({error:'Unsupported image'},502);
      return new Response(data,{headers:{...headers,'Content-Type':mime,'X-Content-Type-Options':'nosniff','Cache-Control':'private, no-store'}});
    }
    return json({error:'Unknown action'},400);
  }catch{
    // Never log download signatures, tokens, or API secrets.
    return json({error:'Media service unavailable'},500);
  }
});
