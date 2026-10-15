import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// ssh2 1.17.0's generator drops valid leading zero bytes from Ed25519 public
// keys. Use OpenSSH for fixtures so encrypted and plain keys are always valid.
export function generateEd25519Key(passphrase = '') {
  const directory = mkdtempSync(join(tmpdir(), '5a-ui-ssh-test-'));
  try {
    const path = join(directory, 'id_ed25519');
    execFileSync('ssh-keygen', [
      '-q', '-t', 'ed25519', '-f', path, '-N', passphrase,
      '-a', '16', '-C', '5a-ui-test',
    ]);
    return readFileSync(path, 'utf8');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
