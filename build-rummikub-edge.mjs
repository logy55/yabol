import{readFile,writeFile}from'node:fs/promises';
const root=new URL('./',import.meta.url),sources=[];
for(const path of ['dist/rummikub/core.js','dist/rummikub/bets.js','supabase/functions/rummikub-room/src/room-core.js','supabase/functions/rummikub-room/src/handler.ts']){
 let source=await readFile(new URL(path,root),'utf8');
 source=source.replace(/^import .* from ['"]\..*['"];\r?\n/gm,'').replace(/^export /gm,'');
 sources.push('// '+path+'\n'+source);
}
await writeFile(new URL('supabase/functions/rummikub-room/index.ts',root),sources.join('\n\n'));
console.log('Bundled authenticated Rummikub Edge Function.');
