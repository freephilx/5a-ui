import { build, type BuildOptions } from 'esbuild';

export async function workerBundle(entry: string, extra: BuildOptions = {}) {
  return build({
    entryPoints: [entry], bundle: true, platform: 'node', format: 'esm', target: 'es2022',
    external: ['node:*'],
    define: { __dirname: '"/"' },
    alias: { 'cpu-features': './src/server/cpu-features.cjs' },
    banner: { js: "import { createRequire as __hryCreateRequire } from 'node:module'; const require = __hryCreateRequire('/worker.js');" },
    plugins: [{ name: 'node-builtins', setup(build) {
      build.onResolve({ filter: /^(crypto|net|dns|events|stream|util|fs|os|http|https|zlib|assert|path|child_process)$/ }, (args) => ({ path: `node:${args.path}`, external: true }));
    } }],
    ...extra,
  });
}
