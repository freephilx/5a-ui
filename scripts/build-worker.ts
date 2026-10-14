import { mkdir } from 'node:fs/promises';
import { workerBundle } from './worker-bundle';
await mkdir('.tmp/worker', { recursive: true });
await workerBundle('src/worker.ts', { outfile: '.tmp/worker/index.mjs', minify: true, sourcemap: false });
console.log('Cloudflare Worker built: .tmp/worker/index.mjs');
