import {build} from 'esbuild';
await build({entryPoints:['src/post-editor.js'],outfile:'dist/post-editor.js',bundle:true,format:'esm',target:'es2022',minify:true,legalComments:'eof'});
