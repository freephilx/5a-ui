import { createServer } from 'vite';
import { nodeHandler } from '../src/server/node-handler';
const server = await createServer({ plugins: [{ name: 'local-api', configureServer(server) { server.middlewares.use((request, response, next) => { if (request.url?.startsWith('/api/')) void nodeHandler(request, response); else next(); }); } }] });
await server.listen();
server.printUrls();
