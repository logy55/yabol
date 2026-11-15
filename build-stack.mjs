import {build} from 'esbuild';
await build({entryPoints:['src/stack-up/index.ts'],bundle:true,format:'esm',target:'es2022',minify:false,legalComments:'inline',banner:{js:'/*! Stack Up — Copyright 2026 DevCol, Apache-2.0. Modified for YABOL. See stack-NOTICE.txt and stack-LICENSE.txt. */'},outfile:'dist/stack-engine.js'});
