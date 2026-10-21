import {build} from 'esbuild';
import {copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root=new URL('./',import.meta.url);
await build({entryPoints:[fileURLToPath(new URL('src/marble/player.ts',root))],bundle:true,format:'esm',target:'es2022',minify:true,external:['fs','path'],legalComments:'inline',outfile:fileURLToPath(new URL('dist/marble-engine.js',root))});
await copyFile(new URL('node_modules/box2d-wasm/dist/es/Box2D.wasm',root),new URL('dist/marble-box2d.wasm',root));
await copyFile(new URL('node_modules/box2d-wasm/LICENSE.zlib.txt',root),new URL('dist/marble-box2d-LICENSE.txt',root));
console.log('Built seeded marble engine and original maps.');
