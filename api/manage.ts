import { nodeHandler } from '../src/server/node-handler';
export default (req: Parameters<typeof nodeHandler>[0], res: Parameters<typeof nodeHandler>[1]) => nodeHandler(req, res, '/api/manage');
