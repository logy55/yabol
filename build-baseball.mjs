import {build} from 'esbuild';
import {mkdir} from 'node:fs/promises';
await build({entryPoints:['src/vendor/matter.cjs'],bundle:true,format:'esm',target:'es2022',platform:'browser',minify:true,outfile:'dist/baseball/matter.js',legalComments:'inline'});
await mkdir('supabase/functions/baseball-score',{recursive:true});
await build({entryPoints:['src/baseball-score.ts'],bundle:true,format:'esm',target:'es2022',platform:'neutral',minify:true,external:['npm:@supabase/supabase-js@2.57.4'],outfile:'supabase/functions/baseball-score/index.ts',legalComments:'inline'});
