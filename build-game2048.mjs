import{build}from'esbuild';import{mkdir}from'node:fs/promises';
await mkdir('supabase/functions/game2048-score',{recursive:true});
await build({entryPoints:['src/game2048-score.ts'],bundle:true,format:'esm',target:'es2022',platform:'neutral',minify:true,external:['npm:@supabase/supabase-js@2.57.4'],outfile:'supabase/functions/game2048-score/index.ts'});
