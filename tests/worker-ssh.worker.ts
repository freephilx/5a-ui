import { runSSH } from '../src/server/ssh';
import { handleAPI } from '../src/server/app';

export default {
  async fetch(request: Request) {
    if (new URL(request.url).pathname.startsWith('/api/')) return handleAPI(request, {}, 'test-ip');
    try {
      const input = await request.json() as Parameters<typeof runSSH>[0];
      return Response.json(await runSSH(input, 'printf worker-ssh-ok\n'));
    } catch (error) {
      return Response.json({ error: String(error), cause: error instanceof Error ? String(error.cause) : undefined }, { status: 500 });
    }
  },
};
