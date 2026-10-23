import {build} from 'esbuild';
await build({entryPoints:['src/replay-video-encoder.js'],bundle:true,format:'esm',target:'es2022',minify:true,legalComments:'inline',outfile:'dist/video-encoder.js'});
